defmodule Kura.Cell.Store do
  @moduledoc "Connects the shared inbox worker to Kura's Ash journal."

  @behaviour Jido.Holon.Store

  alias Kura.Cell.{Inbox, Journal}

  @impl true
  defdelegate enqueue(cell_id, kind, payload, opts), to: Inbox

  @impl true
  defdelegate next(cell_id), to: Inbox

  @impl true
  defdelegate queued_cells(), to: Inbox

  @impl true
  defdelegate resolve(entry, result, trace), to: Journal
end
