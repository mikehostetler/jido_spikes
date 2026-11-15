defmodule Jarvis.Actions.PrepareReview do
  @moduledoc "Recalls memory and sends one current Timer review to VSM System 4."

  use Jido.Action,
    name: "jarvis_prepare_vsm_review",
    schema:
      Jido.Joi.object(%{
        purpose: Jido.Joi.string() |> Jido.Joi.min(1)
      })

  @impl true
  def run(%{purpose: purpose}, %{signal: signal, agent_state: state} = context) do
    with {:ok, generation} <- Jarvis.ReviewSchedule.accepted_generation(state, signal),
         {:ok, rows} <- Jarvis.Plugins.Memory.recall(context, purpose) do
      memories = Enum.map(rows, &Map.take(&1, [:id, :title, :content, :class]))
      data = %{purpose: purpose, memories: memories, generation: generation}

      {:ok, %{status: "queued", generation: generation},
       [Jarvis.Signals.emit(context, "jarvis.vsm.review.requested", data)]}
    else
      :ignore -> {:ok, %{ignored: true}}
      {:error, _} = error -> error
    end
  end
end
