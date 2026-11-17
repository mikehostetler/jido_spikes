defmodule Jarvis do
  @moduledoc "The shared configuration for the local Jarvis demo."

  @model "ollama:qwen3-coder-next:q8_0"

  @doc "Returns the local Ollama model used by Chat and VSM reviews."
  def model, do: @model

  @doc "Returns the local LM Studio model used by Alice."
  def alice_model, do: Jarvis.Alice.Spec.model()
end
