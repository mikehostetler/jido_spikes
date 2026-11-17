defmodule JidoWorkSystem.SimulationTest do
  use JidoWorkSystem.DataCase, async: false

  test "the task contract and organization relationships are complete" do
    snapshot = Simulation.run(:success)
    [task] = snapshot.tasks
    [delegation] = snapshot.delegations
    [accountability] = snapshot.accountabilities
    [parent, child] = Enum.sort_by(snapshot.cells, &is_nil(&1.parent_id), :desc)

    assert task.purpose
    assert task.required_output
    assert task.quantity
    assert task.quality
    assert task.target_completion_time
    assert task.resource_limits
    assert task.discretion_limits
    assert task.escalation_conditions
    assert task.accountable_actor_id == hd(snapshot.humans).id
    assert delegation.task_id == task.id
    assert delegation.authority_id == hd(snapshot.authorities).id
    assert accountability.human_actor_id == task.accountable_actor_id
    assert child.parent_id == parent.id
  end

  test "authority and workspace boundaries deny out-of-scope actions" do
    snapshot = Simulation.run(:success)
    authority = hd(snapshot.authorities)
    workspace = hd(snapshot.workspaces)

    assert Simulation.authorized?(authority, "write")
    refute Simulation.authorized?(authority, "publish")
    assert Simulation.bounded_path?(workspace, workspace.root <> "/release-note.md")
    refute Simulation.bounded_path?(workspace, workspace.root <> "/../outside.txt")
  end

  test "the success path records judgments, receipts, evidence, and acceptance" do
    snapshot = Simulation.run(:success)

    assert Enum.map(snapshot.events, & &1.sequence) == Enum.to_list(1..10)
    assert Enum.map(snapshot.events, & &1.kind) |> List.last() == "human_accepted"
    assert hd(snapshot.tasks).status == "accepted"
    assert hd(snapshot.work).status == "complete"

    selected_method_ids = MapSet.new(Enum.map(snapshot.judgments, & &1.method_id))

    selected_types =
      snapshot.methods
      |> Enum.filter(&MapSet.member?(selected_method_ids, &1.id))
      |> Enum.map(& &1.method_type)
      |> MapSet.new()

    assert selected_types == MapSet.new(~w(htn decision_rule llm))
    assert Enum.all?(snapshot.judgments, &(&1.actor_label == "Writing work cell"))
    assert length(snapshot.decisions) == length(snapshot.judgments)
    assert Enum.all?(snapshot.mutations, &(&1.authorized and byte_size(&1.receipt) == 16))
    assert Enum.all?(snapshot.evidence, & &1.independently_checkable)
    assert hd(snapshot.evaluations).verification_status == "passed"
    assert hd(snapshot.outcomes).human_acceptance == "accepted"
  end

  test "all required judgment method types are registered" do
    types = Simulation.run(:success).methods |> Enum.map(& &1.method_type) |> MapSet.new()
    assert types == MapSet.new(~w(human llm decision_rule classifier optimizer search htn hybrid))
  end

  test "the event sequence and receipts are repeatable" do
    first = Simulation.run(:success)
    second = Simulation.run(:success)

    assert Enum.map(first.events, &{&1.sequence, &1.kind, &1.summary}) ==
             Enum.map(second.events, &{&1.sequence, &1.kind, &1.summary})

    assert Enum.map(first.mutations, & &1.receipt) == Enum.map(second.mutations, & &1.receipt)
  end

  test "the rework path keeps verification separate from human acceptance" do
    snapshot = Simulation.run(:rework)

    assert Enum.map(snapshot.events, & &1.sequence) == Enum.to_list(1..15)
    assert Enum.any?(snapshot.events, &(&1.kind == "rework_requested"))

    assert Enum.map(snapshot.evaluations, & &1.verification_status) |> Enum.sort() == [
             "failed",
             "passed"
           ]

    assert length(snapshot.mutations) == 2
    assert length(snapshot.evidence) == 2
    assert hd(snapshot.outcomes).status == "accepted_after_rework"
    assert hd(snapshot.outcomes).human_acceptance == "accepted"
  end
end
