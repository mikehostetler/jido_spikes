defmodule JidoWorkSystem.ScenarioRunnerTest do
  use JidoWorkSystem.DataCase, async: false

  test "lists the two fixed scenarios" do
    scenarios = Simulation.scenarios()

    assert Enum.map(scenarios, & &1.key) == [
             "straight-through-release",
             "missing-risk-section"
           ]

    assert Enum.all?(scenarios, &(&1.title && &1.summary && &1.learning_point))
  end

  test "starts an empty run and advances one beat at a time" do
    {:ok, state} = Simulation.start_scenario("straight-through-release")

    assert state.run.cursor == 0
    assert state.run.revision == 0
    assert state.run.status == "ready"
    assert state.snapshot.tasks == []
    assert state.snapshot.events == []

    {:ok, stepped} = Simulation.step(state.run.id, 0)

    assert stepped.run.cursor == 1
    assert stepped.run.revision == 1
    assert Enum.map(stepped.snapshot.events, & &1.kind) == ["task_defined"]
    assert hd(stepped.snapshot.tasks).status == "defined"
  end

  test "keeps saved runs isolated" do
    {:ok, first} = Simulation.start_scenario("straight-through-release")
    {:ok, first} = Simulation.step(first.run.id, first.run.revision)
    {:ok, second} = Simulation.start_scenario("missing-risk-section")

    {:ok, reopened_first} = Simulation.get_run(first.run.id)
    {:ok, reopened_second} = Simulation.get_run(second.run.id)

    assert length(reopened_first.snapshot.events) == 1
    assert reopened_second.snapshot.events == []
    assert hd(reopened_first.snapshot.tasks).work_system_id == reopened_first.snapshot.system.id
    assert reopened_second.snapshot.tasks == []
  end

  test "rejects a stale revision without advancing" do
    {:ok, state} = Simulation.start_scenario("straight-through-release")
    {:ok, stepped} = Simulation.step(state.run.id, 0)

    assert {:error, :stale_revision} = Simulation.step(state.run.id, 0)
    {:ok, current} = Simulation.get_run(state.run.id)

    assert current.run.revision == stepped.run.revision
    assert length(current.snapshot.events) == 1
  end

  test "pauses the missing-risk scenario for a revision choice" do
    {:ok, state} = Simulation.start_scenario("missing-risk-section")
    state = step_times(state, 9)

    assert state.run.status == "waiting_for_choice"

    assert state.projection.controls.choices |> Enum.map(& &1.id) == [
             "request_revision",
             "end_run"
           ]

    assert {:error, :choice_required} = Simulation.step(state.run.id, state.run.revision)

    assert {:error, :invalid_choice} =
             Simulation.choose(state.run.id, state.run.revision, "publish")

    {:ok, revised} = Simulation.choose(state.run.id, state.run.revision, "request_revision")
    assert revised.run.status == "running"
    assert List.last(revised.snapshot.events).kind == "rework_requested"

    completed = step_until_done(revised)
    assert completed.run.status == "complete"
    assert hd(completed.snapshot.outcomes).status == "accepted_after_rework"
    assert Enum.map(completed.snapshot.events, & &1.sequence) == Enum.to_list(1..15)
  end

  test "records a human rejection when the player ends the run" do
    {:ok, state} = Simulation.start_scenario("missing-risk-section")
    state = step_times(state, 9)

    {:ok, ended} = Simulation.choose(state.run.id, state.run.revision, "end_run")

    assert ended.run.status == "ended"
    assert hd(ended.snapshot.tasks).status == "rejected"
    assert hd(ended.snapshot.outcomes).human_acceptance == "rejected"
    assert List.last(ended.snapshot.events).kind == "human_rejected"
    assert {:error, :complete} = Simulation.step(ended.run.id, ended.run.revision)
  end

  test "returns controlled errors for unknown identifiers" do
    assert {:error, :unknown_scenario} = Simulation.start_scenario("unknown")
    assert {:error, :not_found} = Simulation.get_run(Ecto.UUID.generate())
  end

  defp step_times(state, count) do
    Enum.reduce(1..count, state, fn _index, current ->
      {:ok, next} = Simulation.step(current.run.id, current.run.revision)
      next
    end)
  end

  defp step_until_done(%{run: %{status: "complete"}} = state), do: state

  defp step_until_done(state) do
    {:ok, next} = Simulation.step(state.run.id, state.run.revision)
    step_until_done(next)
  end
end
