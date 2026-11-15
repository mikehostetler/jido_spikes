defmodule Jarvis.VSM.Passive do
  @moduledoc "A required VSM role that is outside this System 4 to System 5 demo."

  use Jido.Agent, name: "jarvis_vsm_passive"

  state do
    schema(
      Jido.Joi.object(%{
        role: Jido.Joi.string() |> Jido.Joi.default("passive")
      })
    )
  end
end
