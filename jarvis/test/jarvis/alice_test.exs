defmodule Jarvis.AliceTest do
  use ExUnit.Case, async: true

  alias Jarvis.Alice

  alias Jarvis.Alice.{
    Character,
    CognitiveProposal,
    Effect,
    GhostState,
    Prompt,
    Pulse,
    Spec,
    ToolPolicy
  }

  test "the static specification defines the bounded local actor" do
    spec = Spec.default()

    assert %Spec{} = spec
    assert spec.character_module == Character
    assert spec.max_cycles == 100
    assert spec.turn_timeout == 600_000
    assert spec.model =~ "lmstudio:"
    assert Spec.select_strategy(spec, %{}, 1) == :react
  end

  test "one prompt renderer separates every cognitive-cycle input" do
    run =
      Alice.new_run(%{
        "run_directive" => "Read the latest decision before the next judgment.",
        "thought" => "A new signal crossed the network boundary.",
        "mode" => "step",
        "turn_limit" => "3"
      })

    memory = %{id: 12, class: "episodic", content: "Alice observed a stable constraint."}
    pulse = Pulse.new(run, 2, [memory], :react)
    policy = ToolPolicy.for_pulse(pulse, :react)
    rendered = Prompt.render(%{pulse | tool_policy: policy})

    assert rendered.exact =~ "[SYSTEM]"
    assert rendered.exact =~ "Run exactly one cognitive cycle"
    assert rendered.exact =~ "[USER]"
    assert rendered.exact =~ "# Cognitive pulse 2"
    assert rendered.exact =~ run.character_prompt
    assert rendered.exact =~ run.run_directive
    assert rendered.exact =~ "Current ghost-state"
    assert rendered.exact =~ "Alice observed a stable constraint."
    assert rendered.exact =~ "Inner reasoning strategy\nreact"
    assert rendered.exact =~ "Visible tools: latest_decision"
    refute rendered.exact =~ "<alice-next-context>"
    assert [%{type: :text, text: user_input}] = rendered.request_input
    assert user_input == rendered.user

    assert rendered.output_schema["required"] == [
             "narrative",
             "next_state",
             "memories",
             "next_wake"
           ]

    assert String.length(rendered.exact) <= 12_000
  end

  test "the Major character kernel contains identity and voice but no cycle protocol" do
    character = Character.kernel()
    prompt = Character.to_system_prompt(character)

    assert character.id == "jarvis-alice-major"
    assert character.version == 1
    assert character.identity.role =~ "call sign Major"
    assert prompt =~ "# Character: Alice"
    assert prompt =~ "Cybernetic field operative"
    assert prompt =~ "tactically calm"
    assert prompt =~ "truth before comfort"
    assert prompt =~ "replaceable shells"
    assert prompt =~ "canonical Ghost in the Shell character"
    refute prompt =~ "next_wake"
    refute prompt =~ "tool policy"
    refute prompt =~ "cognitive proposal"
  end

  test "a valid proposal replaces the complete ghost-state" do
    output = %{
      "narrative" => "The signal is real, but its source remains unknown.",
      "next_state" => %{
        "situation" => "One verified signal is present.",
        "focus" => "Separate its origin from its meaning.",
        "evidence" => ["The signal repeated twice."],
        "tensions" => ["The source is unknown."],
        "intention" => "Compare it with one trusted baseline.",
        "tool_need" => ""
      },
      "memories" => ["The signal repeated twice without a source."],
      "next_wake" => "continue"
    }

    assert {:ok, proposal} = CognitiveProposal.from_output(output)
    assert proposal.next_state.situation == "One verified signal is present."
    assert proposal.next_state.intention == "Compare it with one trusted baseline."
    assert proposal.memories == ["The signal repeated twice without a source."]
    assert proposal.next_wake == :continue
    refute GhostState.render(proposal.next_state) =~ "Old context"
  end

  test "an incomplete proposal cannot commit" do
    assert {:error, _reason} =
             CognitiveProposal.from_output(%{
               "narrative" => "Incomplete",
               "next_state" => %{"situation" => "Only one field"},
               "memories" => [],
               "next_wake" => "continue"
             })
  end

  test "ordinary pulses disable unrelated shared tools" do
    pulse = pulse("Maintain a quiet background watch.", "Observe one unfamiliar signal.")
    policy = ToolPolicy.for_pulse(pulse, :react)

    assert policy.requirement == :disabled
    assert ToolPolicy.visible_names(policy) == []
  end

  test "explicit needs expose only matching tools" do
    read_pulse =
      pulse("Read the latest decision before the next judgment.", "Review status unknown.")

    write_pulse = pulse("Start the review timer for this investigation.", "A review is needed.")

    assert ToolPolicy.for_pulse(read_pulse, :react).visible == ["latest_decision"]
    assert ToolPolicy.for_pulse(write_pulse, :react).visible == ["start_review"]

    speculative = ToolPolicy.for_pulse(write_pulse, :tree_of_thoughts)
    assert speculative.requirement == :disabled
    assert ToolPolicy.visible_names(speculative) == []
  end

  test "write tool attempts become deterministic effects only after reasoning" do
    pulse = pulse("Start the review timer for this investigation.", "A review is needed.")

    attempt = %{
      status: :ok,
      tool_call_id: "call-1",
      tool_name: "start_review",
      input: %{purpose: "Investigate the network signal"}
    }

    assert {:ok, [first]} = Effect.from_tool_attempts(pulse, [attempt])
    assert {:ok, [second]} = Effect.from_tool_attempts(pulse, [attempt])
    assert first.id == second.id
    assert first.pulse_id == pulse.id
    assert first.status == :pending

    assert {:error, :speculative_strategy_requested_write_effect} =
             Effect.from_tool_attempts(%{pulse | strategy: :tree_of_thoughts}, [attempt])
  end

  test "the staged write tool does not perform the external write" do
    assert {:ok, result} =
             Jarvis.Alice.Tools.StageStartReview.run(
               %{purpose: "Inspect one signal"},
               %{}
             )

    assert result.status == "staged"
    assert result.effect == "start_review"
    assert result.note =~ "has not executed"
  end

  test "each Alice run has an isolated memory and effect namespace" do
    attrs = %{
      "run_directive" => "Observe.",
      "thought" => "One signal.",
      "mode" => "step",
      "turn_limit" => "200"
    }

    first = Alice.new_run(attrs)
    second = Alice.new_run(attrs)

    assert first.id != second.id
    assert first.memory_namespace == first.id
    assert second.memory_namespace == second.id
    assert first.memory_namespace != second.memory_namespace
    assert first.turn_limit == 100
    assert first.pending_effects == []
    assert first.effect_receipts == %{}
  end

  defp pulse(directive, thought) do
    run =
      Alice.new_run(%{
        "run_directive" => directive,
        "thought" => thought,
        "mode" => "step",
        "turn_limit" => "3"
      })

    Pulse.new(run, 1, [], :react)
  end
end
