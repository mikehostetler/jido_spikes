defmodule Jarvis.Agent do
  @moduledoc "The resident Jarvis Agent with Memory, Timer, and one VSM Cell."
  use Jido.Agent,
    name: "jarvis",
    plugins: [
      {Jarvis.Plugins.Memory, %{namespace: "jarvis", store: Jarvis.Memories}},
      Jido.Plugin.Timer
    ]

  state do
    schema(
      Jido.Joi.object(%{
        reviews: Jido.Joi.integer() |> Jido.Joi.default(0),
        review_config: Jido.Joi.map() |> Jido.Joi.default(%{}),
        last_review: Jido.Joi.map() |> Jido.Joi.default(%{})
      })
    )
  end

  routes do
    signal_source("/jarvis")

    route "jarvis.schedule.start", Jarvis.Actions.Schedule, defaults: %{command: :start} do
      state(from: output(:state))
      reply("jarvis.schedule.start.response", from: output(:reply))
    end

    route "jarvis.schedule.pause", Jarvis.Actions.Schedule, defaults: %{command: :pause} do
      state(:unchanged)
      reply("jarvis.schedule.pause.response", from: output(:reply))
    end

    route "jarvis.schedule.resume", Jarvis.Actions.Schedule, defaults: %{command: :resume} do
      state(:unchanged)
      reply("jarvis.schedule.resume.response", from: output(:reply))
    end

    route "jarvis.vsm.review", Jarvis.Actions.PrepareReview do
      state(:unchanged)
      reply("jarvis.vsm.review.response", from: output())
    end

    route("jarvis.vsm.review.completed", Jarvis.Actions.CompleteReview)
  end

  topology do
    agent(:vsm, Jarvis.VSM.Cell)

    connections do
      connect("jarvis.vsm.review.requested", from: :root, to: :vsm)
    end
  end
end
