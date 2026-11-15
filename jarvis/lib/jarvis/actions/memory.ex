defmodule Jarvis.Actions.Memory do
  @moduledoc "Reads or writes explicit memory through the main Agent."
  use Jido.Action,
    name: "jarvis_memory",
    schema:
      Jido.Joi.object(%{
        operation: Jido.Joi.enum([:recall, :remember]),
        text: Jido.Joi.string() |> Jido.Joi.min(1),
        title: Jido.Joi.string() |> Jido.Joi.default("Jarvis memory"),
        class:
          Jido.Joi.enum(~w(semantic episodic procedural working)) |> Jido.Joi.default("semantic")
      })

  @impl true
  def run(input, context) do
    case input.operation do
      :recall ->
        with {:ok, rows} <- Jarvis.Plugins.Memory.recall(context, input.text) do
          {:ok, %{memories: Enum.map(rows, &Map.take(&1, [:id, :title, :content, :class]))}}
        end

      :remember ->
        case Jarvis.Plugins.Memory.remember(context, %{
               title: input.title,
               content: input.text,
               class: input.class
             }) do
          {:ok, row} ->
            {:ok, %{id: row.id}}

          {:error, _changeset} ->
            {:error, Jido.Error.validation_error("Memory could not be stored")}
        end
    end
  end
end
