defmodule Kura.PlaybooksTest do
  use Kura.DataCase, async: false

  alias Kura.{Cells, Playbooks}
  alias Kura.Playbooks.{Fixtures, Runner, Storage, Triage}

  test "binds stored versions to a cell, replays the candidate, and resumes the pinned version" do
    assert {:ok, baseline} = Triage.seed()
    assert baseline.document["type"] == "jido.htn.domain"
    assert {:ok, _} = Playbooks.decode(baseline)
    assert {:error, :unknown_version} = Playbooks.get("pine", baseline.id)

    assert {:ok, waiting} =
             Runner.start(baseline, "ci_snapshot", Fixtures.sparse(), Ash.UUID.generate())

    assert waiting.status == :waiting
    wait = Runner.open_wait(waiting)

    assert {:ok, draft} =
             Playbooks.proposal(baseline, Ash.UUID.generate(), %{"case_id" => "fixture"}, %{
               "method" => "ask_review",
               "condition" => "missing_assertion"
             })

    assert {:error, :unapproved_playbook} = Playbooks.definition(draft)
    assert {:error, :candidate_not_eligible} = Playbooks.approve("cedar", draft.id)
    assert {:ok, compared} = Playbooks.replay("cedar", draft.id)
    assert compared.replay["passed"], inspect(compared.replay)
    assert {:ok, promoted} = Playbooks.approve("cedar", draft.id)
    assert promoted.active

    assert {:ok, loaded} = Storage.get_run(waiting.id)
    assert {:ok, replayed} = Storage.replay_run(waiting.id)
    assert replayed.wait_points == loaded.wait_points
    assert loaded.playbook_ref.playbook_id == baseline.id
    assert {:error, :unmatched_wait} = Runner.resume(loaded, "wrong-id", %{})

    evidence = %{"finding" => Fixtures.review_finding()}
    assert {:ok, finished} = Runner.resume(loaded, wait.id, evidence)
    assert finished.status == :succeeded
    assert Triage.result(finished)["finding"] == evidence["finding"]
    assert {:ok, loaded} = Storage.get_run(waiting.id)
    assert {:ok, ^loaded} = Runner.resume(loaded, wait.id, evidence)
    assert Enum.count(loaded.event_log, &(&1.type == :wait_resolved)) == 1

    assert {:ok, detailed} =
             Runner.start(
               promoted,
               "ci_snapshot",
               Fixtures.snapshot("failure"),
               Ash.UUID.generate()
             )

    assert %{"method" => "use_ci_evidence", "status" => "succeeded", "review_wait" => false} =
             Triage.result(detailed)

    assert {:ok, sparse} =
             Runner.start(promoted, "ci_snapshot", Fixtures.sparse(), Ash.UUID.generate())

    assert %{"method" => "ask_review", "review_wait" => true} = Triage.result(sparse)
  end

  @tag :tmp_dir
  test "Pine drafts, replays, approves, and runs a playbook through its inbox", %{tmp_dir: root} do
    original_root = Application.fetch_env!(:kura, :cell_workspace_root)
    Application.put_env(:kura, :cell_workspace_root, root)
    Phoenix.PubSub.subscribe(Kura.PubSub, "cell:pine")

    on_exit(fn ->
      for {pid, _} <- Registry.lookup(Kura.Cell.Registry, "pine") do
        DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, pid)
      end

      Application.put_env(:kura, :cell_workspace_root, original_root)
    end)

    assert {:error, :unhandled_signal} = Cells.command("cedar/review", :observe)
    assert {:ok, draft_entry} = Cells.command("pine", :observe)
    await_command(draft_entry.id)

    assert {:ok, draft} = Playbooks.get("pine", draft_entry.id)
    assert {:error, :unknown_version} = Playbooks.get("cedar", draft.id)
    assert {:error, :candidate_not_eligible} = Playbooks.approve("pine", draft.id)
    assert {:error, :invalid_fixture_input} = Runner.replay(draft, %{}, %{})

    assert {:ok, replayed} = Playbooks.replay("pine", draft.id)
    assert replayed.replay["passed"]
    assert {:ok, active} = Playbooks.approve("pine", draft.id)
    assert active.active

    assert {:ok, run_entry} = Cells.command("pine", :observe)
    assert %{output: output} = await_command(run_entry.id)
    assert output =~ "Playbook v1 recorded SHA-256"
    assert {:ok, run} = Storage.get_run(run_entry.id)
    assert run.playbook_ref.playbook_id == active.id
    digest = :crypto.hash(:sha256, "Workspace brief for pine.\n") |> Base.encode16(case: :lower)
    assert Runner.result(run)["finding"] == "SHA-256 " <> digest
  end

  defp await_command(id) do
    case Cells.latest_command("pine") do
      %{id: ^id, status: "completed"} = entry ->
        entry

      %{id: ^id, status: "blocked", output: reason} ->
        flunk(reason)

      _ ->
        assert_receive :cell_changed, 5_000
        await_command(id)
    end
  end
end
