defmodule Kura.Cell.Runtime do
  @moduledoc false
  use GenServer

  alias Jido.Signal.Bus
  require Logger
  alias Kura.Cell.{Inbox, Journal, Workspace}

  def ensure(cell) do
    case GenServer.whereis(via(cell.id)) do
      nil ->
        case DynamicSupervisor.start_child(Kura.Cell.Supervisor, {__MODULE__, cell}) do
          {:error, {:already_started, pid}} -> {:ok, pid}
          result -> result
        end

      pid ->
        {:ok, pid}
    end
  end

  def start_link(cell), do: GenServer.start_link(__MODULE__, cell, name: via(cell.id))

  def publish(bus, entry) do
    signal =
      Jido.Signal.new!("kura.cell." <> entry.channel, %{entry_id: entry.id, status: entry.status},
        source: "/cells/" <> entry.cell_id
      )

    Bus.publish(bus, [signal])
    Phoenix.PubSub.broadcast(Kura.PubSub, "cell:" <> entry.cell_id, :cell_changed)
  end

  @impl true
  def init(cell) do
    with {:ok, bus} <- Bus.start_link(name: "kura:" <> cell.id, max_log_size: 100),
         {:ok, workspace} <- Workspace.open(cell) do
      send(self(), :drain)
      {:ok, %{cell: cell, bus: bus, workspace: workspace, active: nil}}
    end
  end

  @impl true
  def handle_cast(:wake, state) do
    send(self(), :drain)
    {:noreply, state}
  end

  @impl true
  def handle_info(:drain, %{active: nil} = state) do
    case Inbox.next(state.cell.id) do
      nil ->
        {:noreply, state}

      entry ->
        kind = entry.kind || entry.input
        handler = Map.get(state.cell.pulse_handlers, kind)

        {result, trace} = run(handler, state, entry)
        {:noreply, commit(%{state | active: {entry, handler, result, trace}})}
    end
  end

  def handle_info(:drain, state), do: {:noreply, state}
  def handle_info(:retry_commit, state), do: {:noreply, commit(state)}

  defp run(nil, _state, _entry), do: {{:error, :unhandled_pulse}, nil}

  defp run(handler, state, entry) do
    handler.run(state.cell, state.workspace, entry)
  catch
    kind, reason ->
      Logger.warning(
        "Cell pulse #{entry.id} stopped: #{Exception.format(kind, reason, __STACKTRACE__)}"
      )

      {{:error, reason}, %{"status" => "error", "reason" => inspect(reason), "tools" => []}}
  end

  defp commit(%{active: {entry, handler, result, trace}} = state) do
    committed =
      if handler && function_exported?(handler, :commit, 3),
        do: handler.commit(entry, result, trace),
        else: Journal.resolve(entry, result, trace)

    case committed do
      {:ok, finished} ->
        publish(state.bus, finished)
        send(self(), :drain)
        %{state | active: nil}

      {:error, error} ->
        Logger.warning("Could not save cell pulse #{entry.id}: #{inspect(error)}")
        Process.send_after(self(), :retry_commit, 1_000)
        state
    end
  end

  defp via(id), do: {:via, Registry, {Kura.Cell.Registry, id}}
end
