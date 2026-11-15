defmodule Jarvis.Actions.CompleteReview do
  @moduledoc "Records the latest current VSM review in the resident Agent."

  use Jido.Action, name: "jarvis_complete_vsm_review", schema: Jido.Joi.map()

  @impl true
  def run(%{generation: generation} = review, %{agent_state: state}) do
    if Jarvis.ReviewSchedule.current_generation?(state, generation) do
      Jarvis.Chat.ReviewNotice.record(state.review_config, review)

      {:ok,
       state
       |> Map.update!(:reviews, &(&1 + 1))
       |> Map.put(:last_review, review)}
    else
      {:ok, state}
    end
  end
end
