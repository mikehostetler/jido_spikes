defmodule JidoWorkSystem.SceneProjectionTest do
  use JidoWorkSystem.DataCase, async: false

  test "initial projection is JSON-safe and ready to step" do
    {:ok, state} = Simulation.start_scenario("straight-through-release")

    assert state.projection.schema_version == 1
    assert state.projection.revision == 0
    assert state.projection.status == "ready"
    assert state.projection.controls.can_step
    assert state.projection.controls.can_play
    assert state.projection.scene.task == nil
    assert state.projection.transition == nil
    assert {:ok, _json} = Jason.encode(state.projection)
  end

  test "projects task handoff and evidence delivery from durable state" do
    {:ok, state} = Simulation.start_scenario("straight-through-release")
    state = step_times(state, 2)

    assert state.projection.current_beat == "delegate_task"
    assert state.projection.scene.task.location == "handoff"
    assert state.projection.transition.kind == "handoff"

    state = step_times(state, 6)

    assert state.projection.current_beat == "record_complete_evidence"
    assert length(state.projection.scene.evidence) == 1
    assert state.projection.transition.kind == "deliver_evidence"
    assert {:ok, _json} = Jason.encode(state.projection)
  end

  test "projects the failed verification choice and final outcome" do
    {:ok, state} = Simulation.start_scenario("missing-risk-section")
    waiting = step_times(state, 9)

    assert waiting.projection.status == "waiting_for_choice"
    assert waiting.projection.scene.verifier.status == "failed"
    refute waiting.projection.controls.can_step
    assert length(waiting.projection.controls.choices) == 2

    {:ok, ended} = Simulation.choose(waiting.run.id, waiting.run.revision, "end_run")

    assert ended.projection.status == "ended"
    assert ended.projection.scene.outcome.human_acceptance == "rejected"
    assert ended.projection.transition.kind == "reject"
    assert {:ok, _json} = Jason.encode(ended.projection)
  end

  defp step_times(state, count) do
    Enum.reduce(1..count, state, fn _index, current ->
      {:ok, next} = Simulation.step(current.run.id, current.run.revision)
      next
    end)
  end
end
