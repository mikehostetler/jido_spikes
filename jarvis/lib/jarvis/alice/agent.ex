defmodule Jarvis.Alice.Agent do
  @moduledoc "The pluggable ReAct reasoner used inside one cognitive cycle."

  use Jido.AI.Agent, name: "alice"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      limits do
        model_calls(8)
        tool_rounds(2)
        retries(0)
        elapsed_ms(600_000)
      end
    end

    tools do
      action(Jarvis.Alice.Tools.StageStartReview)
      action(Jarvis.Alice.Tools.StagePauseReview)
      action(Jarvis.Chat.LatestDecision)
    end
  end
end
