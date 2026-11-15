defmodule Jarvis.Signals do
  @moduledoc "Builds traced Signal directives for the main Agent."

  @doc "Builds an output Signal from the current Agent Turn context."
  def emit(context, type, data) do
    context
    |> Jido.Agent.build_signal(type, data)
    |> Jido.Error.unwrap!()
    |> Jido.Agent.Directive.emit()
  end
end
