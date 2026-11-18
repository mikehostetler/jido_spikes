defmodule Kura.Cell.Pulse do
  @moduledoc "A cell's handler for one durable inbox event."

  @type result :: {:ok, String.t()} | {:error, term()}
  @type trace :: map() | nil

  @callback run(cell :: map(), workspace :: term(), Kura.Work.Entry.t()) :: {result(), trace()}

  @doc "Optionally commit domain state and resolve the entry in the same transaction."
  @callback commit(Kura.Work.Entry.t(), result(), trace()) ::
              {:ok, Kura.Work.Entry.t()} | {:error, term()}
  @optional_callbacks commit: 3
end
