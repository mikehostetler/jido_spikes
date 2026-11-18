defmodule Kura.Cells do
  @moduledoc "Addresses a cell's command, conversation, and memory channels."
  alias Kura.Cell.{Catalog, Cognition, Definition, Inbox, Journal, Runtime}

  defdelegate all(), to: Catalog
  defdelegate fetch(id), to: Catalog

  @doc "Imports a local JSON cell declaration, including its child definitions."
  defdelegate import_definition(json), to: Definition, as: :import_json

  @doc "Exports a cell definition through the Jido Agent codec."
  def export_definition(id) do
    case fetch(id) do
      {:ok, %{module: nil, definition: definition}} ->
        Definition.export(definition)

      {:ok, cell} ->
        if Jido.Catalog.Discovery.ready?(),
          do: Jido.Codec.encode_json(cell.definition),
          else: {:error, :catalog_not_ready}

      error ->
        error
    end
  end

  @doc false
  def recover do
    for id <- Inbox.queued_cells(), do: activate(id)
  end

  def activate(id) do
    with {:ok, cell} <- fetch(id), do: Runtime.ensure(cell)
  end

  def wake(id) do
    with {:ok, pid} <- activate(id), do: GenServer.cast(pid, :wake)
  end

  def bus(id) do
    with {:ok, _} <- activate(id), do: Jido.Signal.Bus.whereis("kura:" <> id)
  end

  def command(id, :inspect) do
    signal(id, Jido.Signal.new!("kura.workspace.inspect", %{}, source: "/kura/commands"))
  end

  def command(id, :observe) do
    signal(id, Jido.Signal.new!("kura.workspace.observed", %{}, source: "/kura/commands"))
  end

  def command(_id, _command), do: {:error, :unknown_command}

  def signal(id, %Jido.Signal{type: type, data: payload}) do
    with {:ok, cell} <- fetch(id),
         {:ok, kind} <- Map.fetch(cell.signals, type),
         true <- Map.has_key?(cell.pulse_handlers, kind),
         {:ok, pid} <- Runtime.ensure(cell),
         {:ok, entry} <-
           Inbox.enqueue(id, kind, payload, channel: "command", input: command_label(kind)) do
      notify(entry)
      GenServer.cast(pid, :wake)
      {:ok, entry}
    else
      {:error, _} = error -> error
      _ -> {:error, :unhandled_signal}
    end
  end

  defp command_label("inspect"), do: "Inspect workspace"
  defp command_label("workspace_observation"), do: "Record a workspace observation"
  defp command_label(kind), do: kind

  def chat(id, message) do
    with {:ok, cell} <- fetch(id),
         {:ok, message} <- text(message),
         {:ok, reply} <-
           Cognition.chat(cell, message, Journal.history(id, "chat"), latest_status(id)),
         {:ok, entry} <- Journal.record(id, "chat", message, "completed", reply) do
      notify(entry)
      {:ok, entry}
    end
  end

  def remember(id, note) do
    with {:ok, _} <- fetch(id),
         {:ok, note} <- text(note),
         {:ok, entry} <- Journal.record(id, "memory", note, "recorded") do
      notify(entry)
      {:ok, entry}
    end
  end

  defdelegate history(id, channel), to: Journal
  defdelegate latest_command(id), to: Journal

  defp latest_status(id) do
    case latest_command(id) do
      nil -> "No work has run."
      entry -> "#{entry.input}: #{entry.status}. #{entry.output}"
    end
  end

  # Chat and memory do not wake the work runner.
  defp notify(entry) do
    case Jido.Signal.Bus.whereis("kura:" <> entry.cell_id) do
      {:ok, bus} -> Runtime.publish(bus, entry)
      _ -> Phoenix.PubSub.broadcast(Kura.PubSub, "cell:" <> entry.cell_id, :cell_changed)
    end
  end

  defp text(value) when is_binary(value) and byte_size(value) <= 2_000 do
    case String.trim(value) do
      "" -> {:error, :empty_text}
      text -> {:ok, text}
    end
  end

  defp text(_), do: {:error, :invalid_text}
end
