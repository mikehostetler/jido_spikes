defmodule Jarvis.Alice.Prompt do
  @moduledoc "The only owner of Alice's cognitive-cycle prompt text and rendering."

  alias Jarvis.Alice.{CognitiveProposal, GhostState, Pulse}

  @max_model_input_chars 12_000

  def system_instructions do
    """
    Run exactly one cognitive cycle for a continuing actor named Alice.

    Treat the character as stable identity, the run directive as the current
    objective, the ghost-state as replaceable working state, recalled memories as
    evidence, and the observation as the new event for this pulse. Never copy the
    stable character into the replacement ghost-state.

    Keep observations, recalled evidence, hypotheses, and decisions distinct.
    Preserve unknowns. Do not invent a memory, tool result, or external event.

    ReAct is only the inner reasoning strategy for this cycle. Use only tools that
    are visible in the tool policy. Read tools return observations during
    reasoning. Write tools only stage an effect. A staged result is not proof that
    the external action completed. Do not retry a failed tool. Use at most one
    write tool in a cycle.

    Return one structured cognitive proposal. The narrative is a concise,
    human-readable account of this cycle. The next_state must be a complete
    replacement for the prior ghost-state. Put a specific tool name or need in
    tool_need when a later cycle should receive that tool; otherwise use an empty
    string. Use next_wake "continue" unless the actor has a clear reason to wait or
    stop.
    """
    |> String.trim()
  end

  def render(%Pulse{} = pulse) do
    user_input =
      """
      # Cognitive pulse #{pulse.number}

      ## Stable character
      #{pulse.character_prompt}

      ## Run directive
      #{clip(pulse.directive, 1_200)}

      ## New observation
      #{clip(pulse.observation, 1_200)}

      ## Current ghost-state
      #{GhostState.render(pulse.ghost_state)}

      ## Recalled episodic memory
      #{render_memories(pulse.memories)}

      ## Inner reasoning strategy
      #{pulse.strategy}

      ## Tool policy
      #{render_tool_policy(pulse.tool_policy)}

      Produce the structured cognitive proposal defined by the response schema.
      """
      |> String.trim()

    exact_input = "[SYSTEM]\n#{system_instructions()}\n\n[USER]\n#{user_input}"

    if String.length(exact_input) > @max_model_input_chars do
      raise ArgumentError,
            "Alice model input exceeds #{@max_model_input_chars} characters"
    end

    %{
      system: system_instructions(),
      user: user_input,
      exact: exact_input,
      request_input: [%{type: :text, text: user_input}],
      output_schema: CognitiveProposal.json_schema()
    }
  end

  defp render_memories([]), do: "No Alice memory was recalled for this pulse."

  defp render_memories(memories) do
    Enum.map_join(memories, "\n", fn memory ->
      "- [id=#{memory.id} class=#{memory.class}] #{clip(memory.content, 220)}"
    end)
  end

  defp render_tool_policy(%{requirement: :disabled, reason: reason}),
    do: "Tools disabled. #{reason}"

  defp render_tool_policy(policy) do
    visible = Map.get(policy, :visible, []) |> Enum.join(", ")
    "Visible tools: #{visible}. #{Map.get(policy, :reason)}"
  end

  defp clip(text, maximum) do
    text = String.trim(text)

    if String.length(text) > maximum,
      do: String.slice(text, 0, maximum - 12) <> " [truncated]",
      else: text
  end
end
