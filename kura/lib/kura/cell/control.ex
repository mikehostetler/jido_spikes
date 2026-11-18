defmodule Kura.Cell.Control do
  @moduledoc false

  alias Jido.AgentServer
  alias Jido.VSM.Cell
  alias Jido.VSM.Signal.ExternalRequest
  alias Kura.Cell.Catalog

  def standard_definition(name) do
    Cell.define(%{name: name, operations: [:delivery, :readiness], adapter: __MODULE__.Adapter})
  end

  def activate(%{id: id, parent: nil, agent_source: source}) do
    with {:ok, address} <- address(id) do
      case Jido.resolve_agent(Kura.Jido, address) do
        {:ok, pid} -> ready(pid)
        {:error, :not_found} -> start_root(address, source)
        {:error, :recovering} -> Jido.activate_agent(Kura.Jido, address)
        error -> error
      end
    end
  end

  def activate(%{id: id, parent: parent, agent_source: source}) do
    with {:ok, parent_cell} <- Catalog.fetch(parent),
         {:ok, _} <- activate(parent_cell),
         {:ok, owner} <- address(parent),
         {:ok, child} <- address(id),
         {:ok, pid} <- attach(owner, child, source) do
      ready(pid)
    end
  end

  def authorize(cell, entry_id) do
    # Use a new VSM correlation ID each time a durable request is retried.
    request_id = entry_id <> ":" <> Ash.UUID.generate()

    signal =
      ExternalRequest.new!(%{request_id: request_id, target: "delivery", payload: %{}})

    with {:ok, root} <- activate(cell),
         {:ok, %{status: :committed}} <- AgentServer.call(root, signal) do
      deadline = System.monotonic_time(:millisecond) + 2_000
      await_command(root_id(cell.id) <> "/$topology/delivery/1", request_id, deadline)
    else
      {:ok, result} -> {:error, {:control_not_committed, result.status}}
      error -> error
    end
  catch
    :exit, _reason -> {:error, :control_unavailable}
  end

  def address(id), do: Jido.agent_address(Kura.Jido, root_id(id))

  defp root_id(id), do: "kura/" <> id

  defp start_root(address, source) do
    case Jido.start_agent(Kura.Jido, source, id: address.id) do
      {:ok, pid} -> ready(pid)
      {:error, {:already_started, _pid}} -> Jido.activate_agent(Kura.Jido, address)
      error -> error
    end
  end

  defp attach(owner, child, source) do
    case Jido.agent_ownership(Kura.Jido, child) do
      {:ok, %{owner_address: ^owner}} ->
        case Jido.resolve_agent(Kura.Jido, child) do
          {:error, :not_found} -> attach_new(owner, child, source)
          result -> result
        end

      {:ok, nil} ->
        attach_new(owner, child, source)

      {:ok, _} ->
        {:error, :wrong_parent}

      {:error, :not_found} ->
        attach_new(owner, child, source)

      error ->
        error
    end
  end

  defp attach_new(owner, child, source) do
    case Cell.attach(Kura.Jido, owner, child, source, request_id: Ash.UUID.generate()) do
      {:ok, pid, _ownership} -> {:ok, pid}
      error -> error
    end
  end

  defp ready(pid) do
    with :ok <- AgentServer.await_ready(pid), do: {:ok, pid}
  end

  defp await_command(id, request_id, deadline) do
    expected = "kura:delivery:" <> request_id

    with pid when is_pid(pid) <- Jido.whereis_agent(Kura.Jido, id),
         %{agent: %{state: %{last_command: ^expected}}} <- AgentServer.snapshot(pid, 500) do
      {:ok, expected}
    else
      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          await_command(id, request_id, deadline)
        else
          {:error, :control_timeout}
        end
    end
  end
end
