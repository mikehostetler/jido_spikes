defmodule Jarvis.VSM.Policy.Record do
  @moduledoc "Records one System 4 review and returns it to the resident Agent."

  use Jido.Action, name: "jarvis_vsm_policy_record", schema: Jido.Joi.map()

  @impl true
  def run(review, %{agent_state: state} = context) do
    state = %{
      state
      | reviews: state.reviews + 1,
        last_review: review
    }

    {:ok, state, [Jarvis.Signals.emit(context, "jarvis.vsm.review.completed", review)]}
  end
end

defmodule Jarvis.VSM.Policy do
  @moduledoc "The active System 5 Agent in the Jarvis VSM demo."

  use Jido.Agent, name: "jarvis_vsm_policy"

  state do
    schema(
      Jido.Joi.object(%{
        reviews: Jido.Joi.integer() |> Jido.Joi.default(0),
        last_review: Jido.Joi.map() |> Jido.Joi.default(%{})
      })
    )
  end

  routes do
    signal_source("/jarvis/vsm/s5")
    route("jarvis.vsm.recommendation", Jarvis.VSM.Policy.Record)
  end
end
