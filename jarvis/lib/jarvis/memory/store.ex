defmodule Jarvis.Memory.Store do
  @moduledoc "The local storage contract used by the Jarvis memory Plugin."

  @callback recall(String.t(), String.t(), keyword()) :: [map()]
  @callback remember(map()) :: {:ok, map()} | {:error, term()}
end
