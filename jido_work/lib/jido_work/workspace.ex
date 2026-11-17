defmodule JidoWork.Workspace do
  @moduledoc """
  Owns the confined Jido VFS filesystem and its attached Jido Shell session.

  Project files use the real `Jido.VFS.Adapter.InMemory` adapter. Shell commands
  use `Jido.Shell.Agent` against the same filesystem. No project tool reads or
  writes the host filesystem.
  """

  use GenServer

  alias Jido.Shell.Agent, as: ShellAgent
  alias Jido.Shell.Command.Parser
  alias Jido.VFS
  alias Jido.VFS.Adapter.InMemory
  alias Jido.VFS.Stat.{Dir, File}

  @allowed_shell_commands ~w(pwd ls cat help)

  @initial_files %{
    "AGENTS.md" => """
    # VFS project instructions

    Keep changes small. Verify an edit through Jido Shell. Do not commit.
    """,
    "README.md" => """
    # VFS Calculator

    `VfsCalculator.add/2` must add two integers. The current implementation is wrong.
    """,
    "lib/calculator.ex" => """
    defmodule VfsCalculator do
      def add(left, right), do: left - right
    end
    """,
    "test/calculator_test.exs" => """
    defmodule VfsCalculatorTest do
      use ExUnit.Case

      test "adds two integers" do
        assert VfsCalculator.add(2, 3) == 5
      end
    end
    """
  }

  def filesystem, do: InMemory.configure(name: __MODULE__)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def reset, do: GenServer.call(__MODULE__, :reset)
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def list_files(pattern \\ ""), do: GenServer.call(__MODULE__, {:list_files, pattern})
  def read_file(path), do: GenServer.call(__MODULE__, {:read_file, path})
  def search_text(query), do: GenServer.call(__MODULE__, {:search_text, query})

  def edit_file(path, old_text, new_text),
    do: GenServer.call(__MODULE__, {:edit_file, path, old_text, new_text})

  def run_shell(command), do: GenServer.call(__MODULE__, {:run_shell, command}, 10_000)

  def require_skill(name, resources),
    do: GenServer.call(__MODULE__, {:require_skill, name, resources})

  def mark_skill_loaded(name), do: GenServer.call(__MODULE__, {:mark_skill_loaded, name})

  def mark_skill_resource_loaded(name, path),
    do: GenServer.call(__MODULE__, {:mark_skill_resource_loaded, name, path})

  def check_skill_gate, do: GenServer.call(__MODULE__, :check_skill_gate)

  def set_script_scenario(scenario),
    do: GenServer.call(__MODULE__, {:set_script_scenario, scenario})

  def next_script_step, do: GenServer.call(__MODULE__, :next_script_step)

  def record_event(tool, arguments, result) do
    GenServer.cast(__MODULE__, {:record_event, tool, arguments, result})
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init(:ok) do
    with :ok <- reset_filesystem(),
         {:ok, session} <- start_shell_session() do
      {:ok, new_state(session)}
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    with :ok <- stop_shell_session(state.shell_session),
         :ok <- reset_filesystem(),
         {:ok, session} <- start_shell_session() do
      {:reply, :ok, new_state(session)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      files: filesystem_files(),
      events: Enum.reverse(state.events),
      skill_gate: skill_gate_status(state.skill_gate),
      runtime: %{
        filesystem: "Jido.VFS.Adapter.InMemory",
        shell: "Jido.Shell.Agent"
      }
    }

    {:reply, snapshot, state}
  end

  def handle_call({:require_skill, name, resources}, _from, state) do
    gate = %{
      name: name,
      root_loaded?: false,
      required_resources: MapSet.new(resources),
      loaded_resources: MapSet.new()
    }

    {:reply, :ok, %{state | skill_gate: gate}}
  end

  def handle_call({:mark_skill_loaded, name}, _from, %{skill_gate: gate} = state) do
    next_gate =
      if gate && gate.name == name,
        do: %{gate | root_loaded?: true},
        else: gate

    {:reply, :ok, %{state | skill_gate: next_gate}}
  end

  def handle_call(
        {:mark_skill_resource_loaded, name, path},
        _from,
        %{skill_gate: gate} = state
      ) do
    next_gate =
      if gate && gate.name == name && gate.root_loaded? do
        %{gate | loaded_resources: MapSet.put(gate.loaded_resources, path)}
      else
        gate
      end

    {:reply, :ok, %{state | skill_gate: next_gate}}
  end

  def handle_call(:check_skill_gate, _from, state) do
    {:reply, skill_gate_result(state.skill_gate), state}
  end

  def handle_call({:set_script_scenario, scenario}, _from, state)
      when scenario in [:jido, :tutor] do
    {:reply, :ok, %{state | script_scenario: scenario, script_step: 0}}
  end

  def handle_call(:next_script_step, _from, state) do
    value = {state.script_scenario, state.script_step}
    {:reply, value, %{state | script_step: state.script_step + 1}}
  end

  def handle_call({:list_files, pattern}, _from, state) do
    files = filesystem_files() |> Map.keys() |> Enum.sort() |> filter_files(pattern)
    result = %{files: files, count: length(files), filesystem: "jido_vfs"}
    {:reply, {:ok, result}, add_event(state, "list_files", %{pattern: pattern}, result)}
  end

  def handle_call({:read_file, path}, _from, state) do
    result =
      case VFS.read(filesystem(), path) do
        {:ok, content} ->
          {:ok,
           %{path: path, content: content, bytes: byte_size(content), filesystem: "jido_vfs"}}

        {:error, error} ->
          {:error, vfs_error(error, path)}
      end

    {:reply, result, add_event(state, "read_file", %{path: path}, summarize(result))}
  end

  def handle_call({:search_text, query}, _from, state) do
    matches =
      filesystem_files()
      |> Enum.flat_map(fn {path, content} ->
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _number} -> String.contains?(line, query) end)
        |> Enum.map(fn {line, number} -> %{path: path, line: number, text: line} end)
      end)

    result = %{query: query, matches: matches, count: length(matches), filesystem: "jido_vfs"}
    {:reply, {:ok, result}, add_event(state, "search_text", %{query: query}, result)}
  end

  def handle_call({:edit_file, path, old_text, new_text}, _from, state) do
    result = checked_edit(path, old_text, new_text)

    arguments = %{path: path, old_text: old_text, new_text: new_text}
    {:reply, result, add_event(state, "edit_file", arguments, summarize(result))}
  end

  def handle_call({:run_shell, command}, _from, state) do
    result = run_allowed_shell(state.shell_session, command)
    {:reply, result, add_event(state, "run_shell", %{command: command}, summarize(result))}
  end

  @impl true
  def handle_cast({:record_event, tool, arguments, result}, state) do
    {:noreply, add_event(state, tool, arguments, summarize(result))}
  end

  @impl true
  def terminate(_reason, state) do
    _ = stop_shell_session(state.shell_session)
    :ok
  end

  defp reset_filesystem do
    with :ok <- VFS.clear(filesystem()) do
      Enum.reduce_while(@initial_files, :ok, fn {path, content}, :ok ->
        case VFS.write(filesystem(), path, content) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp start_shell_session, do: ShellAgent.new(filesystem(), owner: self())

  defp stop_shell_session(session) do
    case ShellAgent.stop(session) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, _} = error -> error
    end
  end

  defp new_state(session) do
    %{
      shell_session: session,
      events: [],
      script_scenario: :jido,
      script_step: 0,
      skill_gate: nil
    }
  end

  defp checked_edit(path, old_text, new_text) do
    with {:ok, content} <- VFS.read(filesystem(), path),
         true <- old_text != "" && String.contains?(content, old_text),
         next = String.replace(content, old_text, new_text, global: false),
         :ok <- VFS.write(filesystem(), path, next) do
      {:ok,
       %{
         path: path,
         changed: true,
         bytes: byte_size(next),
         filesystem: "jido_vfs"
       }}
    else
      false -> {:error, %{type: :text_not_found, path: path}}
      {:error, error} -> {:error, vfs_error(error, path)}
    end
  end

  defp run_allowed_shell(session, command) do
    with {:ok, program} <- Parser.parse_program(command),
         :ok <- allow_shell_program(program),
         {:ok, output} <- ShellAgent.run(session, command, timeout: 5_000) do
      {:ok, %{command: command, output: output, shell: "jido_shell"}}
    else
      {:error, %Jido.Shell.Error{} = error} ->
        {:error,
         %{
           type: :shell_error,
           code: inspect(error.code),
           message: Exception.message(error)
         }}

      {:error, reason} when is_atom(reason) ->
        {:error, %{type: :shell_parse_error, reason: reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp allow_shell_program(program) do
    disallowed = Enum.reject(program, &(&1.command in @allowed_shell_commands))

    if disallowed == [] do
      :ok
    else
      {:error,
       %{
         type: :shell_command_not_allowed,
         requested: Enum.map(disallowed, & &1.command),
         allowed: @allowed_shell_commands
       }}
    end
  end

  defp filesystem_files do
    case collect_files("") do
      {:ok, files} -> Map.new(files)
      {:error, _reason} -> %{}
    end
  end

  defp collect_files(directory) do
    case VFS.list_contents(filesystem(), directory) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
          path = if directory == "", do: entry.name, else: Path.join(directory, entry.name)

          case entry do
            %File{} ->
              case VFS.read(filesystem(), path) do
                {:ok, content} -> {:cont, {:ok, [{path, content} | acc]}}
                {:error, reason} -> {:halt, {:error, reason}}
              end

            %Dir{} ->
              case collect_files(path) do
                {:ok, nested} -> {:cont, {:ok, nested ++ acc}}
                {:error, reason} -> {:halt, {:error, reason}}
              end
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp skill_gate_result(nil), do: :ok

  defp skill_gate_result(%{root_loaded?: false, name: name}) do
    {:error,
     %{
       type: :skill_required,
       message: "Load the required skill before using project tools.",
       required_tool: "load_skill",
       required_arguments: %{name: name}
     }}
  end

  defp skill_gate_result(gate) do
    missing = MapSet.difference(gate.required_resources, gate.loaded_resources)

    if MapSet.size(missing) == 0 do
      :ok
    else
      path = missing |> Enum.sort() |> List.first()

      {:error,
       %{
         type: :skill_resource_required,
         message: "Load the required skill resource before using project tools.",
         required_tool: "load_skill_resource",
         required_arguments: %{name: gate.name, path: path}
       }}
    end
  end

  defp skill_gate_status(nil), do: %{status: :not_required}

  defp skill_gate_status(gate) do
    missing =
      gate.required_resources
      |> MapSet.difference(gate.loaded_resources)
      |> Enum.sort()

    status = if gate.root_loaded? && missing == [], do: :satisfied, else: :waiting

    %{
      status: status,
      name: gate.name,
      root_loaded?: gate.root_loaded?,
      missing_resources: missing
    }
  end

  defp filter_files(files, pattern) when pattern in [nil, "", "*", "**/*"], do: files

  defp filter_files(files, pattern),
    do: Enum.filter(files, &String.contains?(&1, String.trim(pattern, "*")))

  defp vfs_error(error, path) do
    %{
      type: :vfs_error,
      path: path,
      message: if(is_exception(error), do: Exception.message(error), else: inspect(error))
    }
  end

  defp add_event(state, tool, arguments, result) do
    event = %{
      id: System.unique_integer([:positive, :monotonic]),
      at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      tool: tool,
      arguments: arguments,
      result: result
    }

    Map.update!(state, :events, &[event | &1])
  end

  defp summarize({:ok, value}), do: summarize(value)
  defp summarize({:error, value}), do: %{error: inspect(value)}

  defp summarize(%{} = value) do
    value
    |> Map.drop([
      :content,
      "content",
      :instructions,
      "instructions",
      :resources,
      "resources"
    ])
    |> Map.put(:summary, summary_text(value))
  end

  defp summarize(value), do: inspect(value, limit: 8, printable_limit: 300)

  defp summary_text(value) do
    cond do
      Map.has_key?(value, :instructions) -> "Skill instructions loaded."
      Map.has_key?(value, :content) -> "VFS text resource loaded."
      Map.get(value, :shell) == "jido_shell" -> "Jido Shell command completed."
      true -> inspect(value, limit: 8, printable_limit: 300)
    end
  end
end
