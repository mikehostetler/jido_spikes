defmodule Section9.Fixture do
  @moduledoc "Fixed repair fixture and protected acceptance runner."

  @root Path.expand("../..", __DIR__)
  @broken Path.join(@root, "fixture/snapshots/broken_job_server.ex")
  @runner Path.join(@root, "fixture/acceptance_runner.exs")
  @workspace Path.join(@root, "fixture/workspace/lib/job_server.ex")

  def broken_source, do: File.read!(@broken)

  def repaired_source do
    """
    defmodule Section9Fixture.JobServer do
      use GenServer

      def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})
      def start(server, ref, owner \\\\ self()), do: GenServer.call(server, {:start, ref, owner})
      def cancel(server, ref), do: GenServer.call(server, {:cancel, ref})
      def deliver(server, ref, value), do: GenServer.cast(server, {:result, ref, value})
      def sync(server), do: GenServer.call(server, :sync)

      @impl true
      def init(state), do: {:ok, state}

      @impl true
      def handle_call({:start, ref, owner}, _from, pending) do
        {:reply, :ok, Map.put(pending, ref, owner)}
      end

      def handle_call({:cancel, ref}, _from, pending) do
        case Map.pop(pending, ref) do
          {nil, next} -> {:reply, :ok, next}
          {owner, next} ->
            send(owner, {:job_cancelled, ref})
            {:reply, :ok, next}
        end
      end

      def handle_call(:sync, _from, pending), do: {:reply, :ok, pending}

      @impl true
      def handle_cast({:result, ref, value}, pending) do
        case Map.pop(pending, ref) do
          {nil, next} -> {:noreply, next}
          {owner, next} ->
            send(owner, {:job_result, ref, value})
            {:noreply, next}
        end
      end
    end
    """
  end

  def acceptance_contract do
    """
    Protected acceptance checks require normal completion exactly once,
    cancellation cleanup, rejection of late and duplicate results, process
    survival, and successful work after cancellation. Tests use message refs
    and a synchronous mailbox barrier. They do not use sleeps.
    """
    |> String.trim()
  end

  def reset_workspace do
    File.mkdir_p!(Path.dirname(@workspace))
    File.write!(@workspace, broken_source())
    @workspace
  end

  def materialize(source) when is_binary(source) do
    File.mkdir_p!(Path.dirname(@workspace))
    File.write!(@workspace, source)
    @workspace
  end

  def run_acceptance(source) when is_binary(source) do
    started = System.monotonic_time(:millisecond)
    run_dir = Path.join(@root, "fixture/runs/#{System.unique_integer([:positive])}")
    File.mkdir_p!(run_dir)
    candidate = Path.join(run_dir, "job_server.ex")
    File.write!(candidate, source)

    {output, status} =
      System.cmd(System.find_executable("elixir"), [@runner],
        env: [{"SECTION9_CANDIDATE", candidate}],
        stderr_to_stdout: true
      )

    %{
      passed: status == 0,
      status: status,
      command: "elixir fixture/acceptance_runner.exs",
      output: output,
      elapsed_ms: System.monotonic_time(:millisecond) - started,
      checks: ["normal", "cancel", "late_result", "duplicate_result", "regression"]
    }
  end

  def baseline, do: run_acceptance(broken_source())

  def diff(source) do
    left = String.split(broken_source(), "\n")
    right = String.split(source, "\n")

    List.myers_difference(left, right)
    |> Enum.map_join("\n", fn
      {:eq, lines} -> Enum.map_join(lines, "\n", &("  " <> &1))
      {:del, lines} -> Enum.map_join(lines, "\n", &("- " <> &1))
      {:ins, lines} -> Enum.map_join(lines, "\n", &("+ " <> &1))
    end)
  end
end
