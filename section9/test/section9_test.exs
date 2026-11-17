defmodule Section9Test do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest

  @endpoint Section9Web.Endpoint

  alias Section9.{
    Actor,
    Fixture,
    Ledger,
    Proposal,
    RolePolicy,
    SkillPackage,
    Team,
    ViableWorkCell
  }

  setup do
    :ok = Ledger.reset_demo()
    :ok = SkillPackage.load_all()
    Fixture.reset_workspace()
    :ok
  end

  test "all stable actor identities have the Jido root and command registry loaded" do
    actors = Ledger.snapshot().actors

    assert Enum.map(actors, & &1.role) == ["evaluator", "implementer", "lead"]

    for actor <- actors do
      assert [%{name: "jido", resources: resources}] = actor.skills
      assert Enum.any?(resources, &(&1[:path] == "SKILL.md"))
      assert Enum.any?(resources, &(&1[:path] == "references/commands.md"))
    end
  end

  test "baseline fails and the fixed candidate passes protected deterministic checks" do
    baseline = Fixture.baseline()
    repaired = Fixture.run_acceptance(Fixture.repaired_source())

    refute baseline.passed
    assert baseline.status != 0
    assert repaired.passed
    assert repaired.status == 0

    assert repaired.checks == [
             "normal",
             "cancel",
             "late_result",
             "duplicate_result",
             "regression"
           ]
  end

  test "role policy blocks evaluator repair and lead closure before evaluation" do
    assert RolePolicy.writable_paths(:evaluator) == []

    assert {:error, {:action_not_allowed, :evaluator, "submit_candidate"}} =
             Proposal.validate(:evaluator, %{
               "narrative" => "I changed it.",
               "next_state" => valid_state(),
               "action" => %{"type" => "submit_candidate", "source" => "bad"}
             })

    assert {:error, {:evaluation_required, "pending"}} =
             Ledger.commit_pulse(
               :lead,
               "early-close",
               %{},
               valid_state(),
               proposal("close_mission"),
               0
             )
  end

  test "duplicate delivery returns the stored receipt and does not add a pulse" do
    before = Ledger.context(:lead).actor.state
    proposed = proposal("assign_implementer")

    assert {:ok, receipt} =
             Ledger.commit_pulse(:lead, "same-delivery", %{}, before, proposed, 0)

    assert {:duplicate, ^receipt} =
             Ledger.commit_pulse(:lead, "same-delivery", %{}, before, proposed, 0)

    assert Ledger.snapshot().mission.pulses_used == 1
  end

  test "a replacement claim rejects a stale candidate result" do
    assert {:ok, _} = Team.step(:lead, model_adapter: Section9.Model.Fake)
    assert {:ok, 2} = Ledger.expire_and_reclaim(:implementer)

    assert {:error, {:stale_generation, 1, 2}} =
             Ledger.save_uncertain_candidate("stale-effect", Fixture.repaired_source(), 1)
  end

  test "deterministic fake model closes a complete mission" do
    assert {:ok, receipts} = Team.run_auto(model_adapter: Section9.Model.Fake)
    assert length(receipts) == 4

    snapshot = Ledger.snapshot()
    assert snapshot.task.status == "closed"
    assert snapshot.mission.status == "closed"
    assert snapshot.evaluation.passed
    assert snapshot.mission.pulses_used == 4
  end

  test "supervision reconciles a candidate saved before the implementer reports completion" do
    assert {:ok, _} = Team.step(:lead, model_adapter: Section9.Model.Fake)
    old_pid = Actor.pid(:implementer)
    monitor = Process.monitor(old_pid)
    parent = self()
    :ok = Actor.interrupt_next(:implementer)

    spawn(fn ->
      result =
        try do
          Actor.pulse(:implementer, model_adapter: Section9.Model.Fake)
        catch
          :exit, reason -> {:exit, reason}
        end

      send(parent, {:pulse_result, result})
    end)

    assert_receive {:DOWN, ^monitor, :process, ^old_pid, :injected_after_candidate_save}, 5_000
    assert_receive {:pulse_result, {:exit, _reason}}, 5_000
    new_pid = wait_for_restarted_actor(:implementer, old_pid, 5_000)
    assert is_pid(new_pid)

    recovered = Ledger.snapshot()
    assert recovered.task.status == "candidate_ready"
    assert recovered.task.claim_generation == 1
    assert Enum.any?(recovered.events, &(&1.type == "candidate_saved_before_report"))
    assert Enum.any?(recovered.events, &(&1.type == "uncertain_candidate_reconciled"))

    assert {:ok, _} = Team.run_auto(model_adapter: Section9.Model.Fake)
    assert Ledger.snapshot().mission.status == "closed"
  end

  test "LiveView initial response exposes task, generation, skill, and evidence panels" do
    conn = get(build_conn(), "/")
    body = html_response(conn, 200)

    assert body =~ "Persistent Repair Team"
    assert body =~ "Claim generation"
    assert body =~ "Evaluation evidence"
    assert body =~ "Shared ledger timeline"
  end

  test "viable work cell completes the full VSM and repair loop" do
    assert {:ok, report} = ViableWorkCell.run(work_contract("cell-normal"))

    assert report.recursive_state.operations == ["delivery", "learning"]
    assert report.recursive_state.management_roles == ["s2", "s3", "s3_star", "s4", "s5"]
    assert report.recursive_state.resident_agents == 8
    assert report.sense.pressure == :normal
    assert report.authorize.decision == :authorized
    assert report.verify.passed
    assert report.verify.mission == "closed"
    assert report.remember.work_ledger == :sqlite
  end

  test "viable work cell sends human pain steering through control and policy" do
    assert {:ok, result} = ViableWorkCell.steer(:pain, "Human asks the cell to slow down")

    assert result.level == :pain
    assert result.s3.pain_count >= 1
    assert result.s5.pain_count >= 1
  end

  test "viable work cell blocks effects after an emergency signal" do
    assert {:error, {:work_escalated, %{reason: :emergency_stop}}} =
             ViableWorkCell.run(work_contract("cell-emergency"), pressure: :emergency)

    snapshot = Ledger.snapshot()
    assert snapshot.mission.status == "active"
    assert snapshot.task.status == "pending"
  end

  test "human actor delegates a prescribed task and accepts verified work" do
    assert {:ok, simulation} = Section9.HumanWorkSimulation.run(id: "human-normal")

    assert simulation.status == :accept
    assert simulation.accountable_actor == "human-owner"
    assert simulation.task.output == "One repaired JobServer candidate"
    assert simulation.task.accountable_role == :human_owner
    assert simulation.task.by_when == "before the end of this simulation"
    assert simulation.cell.outcome |> elem(0) == :ok

    assert Enum.map(simulation.human.judgments, & &1.decision) == [:delegate, :accept]
  end

  test "human actor respects an emergency stop from the work cell" do
    assert {:ok, simulation} =
             Section9.HumanWorkSimulation.run(id: "human-emergency", pressure: :emergency)

    assert simulation.status == :stopped

    assert Enum.map(simulation.human.judgments, & &1.decision) == [
             :delegate,
             :stop_and_review
           ]

    assert {:error, {:work_escalated, %{reason: :emergency_stop}}} = simulation.cell.outcome
    assert Ledger.snapshot().task.status == "pending"
  end

  defp proposal(action) do
    %{
      "narrative" => "One checked action.",
      "next_state" => valid_state(),
      "action" => %{"type" => action},
      "audit" => %{}
    }
  end

  defp valid_state do
    %{"focus" => "Current work.", "facts" => ["Committed fact."], "next_step" => "Continue."}
  end

  defp work_contract(id) do
    %{
      id: id,
      purpose: "Repair the deterministic JobServer fixture",
      done_when: "Protected checks pass and the mission closes",
      authority: :local_write,
      budget: %{pulses: 12, cost_usd: 0}
    }
  end

  defp wait_for_restarted_actor(role, old_pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(role, old_pid, deadline)
  end

  defp do_wait(role, old_pid, deadline) do
    case Actor.pid(role) do
      pid when is_pid(pid) and pid != old_pid ->
        pid

      _ ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("actor did not restart")
        else
          receive do
          after
            1 -> do_wait(role, old_pid, deadline)
          end
        end
    end
  end
end
