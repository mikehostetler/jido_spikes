defmodule Jarvis.Alice.Pulse do
  @moduledoc "The complete typed input to one cognitive cycle."

  @enforce_keys [
    :id,
    :run_id,
    :number,
    :observation,
    :character,
    :character_prompt,
    :directive,
    :ghost_state,
    :memories,
    :strategy,
    :tool_policy
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          run_id: String.t(),
          number: pos_integer(),
          observation: String.t(),
          character: struct(),
          character_prompt: String.t(),
          directive: String.t(),
          ghost_state: Jarvis.Alice.GhostState.t(),
          memories: [map()],
          strategy: Jarvis.Alice.Spec.strategy(),
          tool_policy: map() | nil
        }

  def new(run, number, memories, strategy, tool_policy \\ nil) do
    %__MODULE__{
      id: "#{run.id}:pulse:#{number}",
      run_id: run.id,
      number: number,
      observation: observation(run, number),
      character: run.character,
      character_prompt: run.character_prompt,
      directive: run.run_directive,
      ghost_state: run.ghost_state,
      memories: memories,
      strategy: strategy,
      tool_policy: tool_policy
    }
  end

  defp observation(run, 1), do: run.initial_thought
  defp observation(_run, _number), do: "No new external observation arrived before this pulse."
end
