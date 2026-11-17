defmodule Jarvis.Alice.Tools.StageStartReview do
  @moduledoc "Stages a shared review start without performing the write during reasoning."

  use Jido.Action,
    name: "start_review",
    description:
      "Stage a request to start or replace the shared VSM review timer after this pulse commits.",
    schema:
      Jido.Joi.object(%{purpose: Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.max(8_000)})

  @impl true
  def run(%{purpose: purpose}, _context) do
    {:ok,
     %{
       status: "staged",
       effect: "start_review",
       purpose: purpose,
       note: "The write has not executed. It can run only after the cognitive cycle commits."
     }}
  end
end

defmodule Jarvis.Alice.Tools.StagePauseReview do
  @moduledoc "Stages a shared review pause without performing the write during reasoning."

  use Jido.Action,
    name: "pause_review",
    description: "Stage a request to pause the shared VSM review timer after this pulse commits.",
    schema: Jido.Joi.object(%{})

  @impl true
  def run(_input, _context) do
    {:ok,
     %{
       status: "staged",
       effect: "pause_review",
       note: "The write has not executed. It can run only after the cognitive cycle commits."
     }}
  end
end
