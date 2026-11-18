defmodule Kura.MaintenanceTest do
  use Kura.DataCase, async: false

  alias Kura.Cell.{Catalog, Control, Inbox}
  alias Kura.Maintenance
  alias Kura.Playbooks.{Fixtures, Storage}
  alias Kura.Work.{Entry, MaintenanceCase}

  test "CI, Review and closure use the inbox with an exact-head gate" do
    on_exit(fn ->
      for {pid, _} <- Registry.lookup(Kura.Cell.Registry, "cedar/review") do
        DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, pid)
      end
    end)

    Maintenance.subscribe()
    assert {:error, :fixture_out_of_order} = Maintenance.apply_fixture("pass")
    assert {:ok, opened} = Maintenance.apply_fixture("failure")
    assert [%{"id" => failure_pulse, "type" => "ci_snapshot"}] = Maintenance.pending(opened)
    assert %{id: id, state: reviewed} = await_ready()
    assert id == opened.id
    assert reviewed["phase"] == "waiting_ci"

    assert [delegation, review] =
             Enum.filter(reviewed["events"], &Map.has_key?(&1["evidence"], "receipt"))

    assert delegation["actor"] == "Cedar"
    assert review["actor"] == "Review"
    assert review["evidence"]["head"] == reviewed["original_head"]
    assert review["evidence"]["receipt"] =~ "kura:delivery:"

    assert [%{"pulse_id" => ^failure_pulse}, %{"trigger" => "review_reply"}] = pulses(reviewed)

    assert {:ok, advanced} = Maintenance.apply_fixture("new_head")
    refute advanced.state["current_head"] == reviewed["original_head"]
    await_ready()
    assert {:ok, stale} = Maintenance.apply_fixture("stale_pass")
    assert stale.state["phase"] == "waiting_ci"
    assert stale.state["current_head"] == advanced.state["current_head"]
    await_ready()
    assert {:error, :fixture_out_of_order} = Maintenance.apply_fixture("stale_pass")

    assert {:ok, closed} = Maintenance.apply_fixture("pass")
    assert closed.id == id
    assert closed.state["phase"] == "closed"
    assert closed.state["current_head"] == advanced.state["current_head"]

    assert [%{"type" => "ci_snapshot"}, %{"type" => "case_closed", "id" => closure_id}] =
             Maintenance.pending(closed)

    finished = await_ready()

    assert [
             "ci_snapshot",
             "review_reply",
             "ci_snapshot",
             "ci_snapshot",
             "ci_snapshot",
             "case_closed"
           ] ==
             Enum.map(pulses(finished.state), & &1["trigger"])

    assert %{"pulse_id" => ^closure_id} = List.last(pulses(finished.state))

    entries = Inbox.scoped_events("cedar", id)
    assert Enum.map(entries, & &1.id) == Enum.map(pulses(finished.state), & &1["pulse_id"])
    assert Enum.all?(entries, &(&1.status == "completed" and &1.trace["status"] == "local_demo"))
    refute Map.has_key?(finished.state, "inbox")
  end

  test "startup drains a saved closure pulse once" do
    Maintenance.subscribe()
    pulse_id = Ash.UUID.generate()
    original = String.duplicate("a", 40)
    head = String.duplicate("b", 40)

    state = %{
      "phase" => "closed",
      "original_head" => original,
      "current_head" => head,
      "fixtures" => ["failure", "new_head", "stale_pass", "pass"],
      "events" => [%{"actor" => "CI", "evidence" => %{"head" => original}}],
      "inbox" => [
        %{
          "id" => pulse_id,
          "type" => "case_closed",
          "payload" => %{"passing_check" => %{"check_head" => head, "status" => "passed"}}
        }
      ]
    }

    assert {:ok, %{id: id}} = Ash.create(MaintenanceCase, %{state: state}, action: :open)
    assert Maintenance.next_fixture(Maintenance.current()) == nil

    Application.put_env(:kura, :recover_cells_on_boot, true)

    try do
      restart_maintenance()
      assert %{id: ^id, state: recovered} = await_ready()
      assert [%{"pulse_id" => ^pulse_id, "trigger" => "case_closed"}] = pulses(recovered)
      restart_maintenance()
      assert %{id: ^id, state: ^recovered} = Maintenance.current()
    after
      Application.put_env(:kura, :recover_cells_on_boot, false)
    end
  end

  test "a failed Loom start blocks the case and its pulse" do
    Maintenance.subscribe()
    failed = Fixtures.snapshot("failure")

    state = %{
      "phase" => "waiting_ci",
      "original_head" => failed["head"],
      "current_head" => failed["head"],
      "triage_version" => "missing-version",
      "fixtures" => ["failure"],
      "events" => [%{"actor" => "CI", "evidence" => failed}]
    }

    assert {:ok, record} = Ash.create(MaintenanceCase, %{state: state}, action: :open)
    assert {:ok, pulse} = Inbox.enqueue("cedar", "ci_snapshot", failed, scope_id: record.id)
    assert :ok = Kura.Cells.wake("cedar")
    assert %{state: %{"phase" => "blocked"}} = await_ready()
    assert {:ok, %{status: "blocked"}} = Ash.get(Entry, pulse.id)
    assert {:error, :fixture_out_of_order} = Maintenance.apply_fixture("new_head")
  end

  test "a saved Review request survives a control error and a maintenance restart" do
    Maintenance.subscribe()
    assert {:ok, cedar} = Catalog.fetch("cedar")
    assert {:ok, _} = Control.activate(cedar)
    delivery = Jido.whereis_agent(Kura.Jido, "kura/cedar/$topology/delivery/1")
    assert is_pid(delivery)

    assert {:ok, _} = Maintenance.apply_fixture("failure_sparse")

    %{id: id, state: %{"playbook" => %{"run_id" => run_id, "wait_id" => wait_id}}} =
      await_case(fn record -> Maintenance.fixture_review_available?(record) end)

    :sys.suspend(delivery)
    Application.put_env(:kura, :recover_cells_on_boot, true)

    try do
      assert {:ok, _} = Maintenance.apply_fixture("review_reply")

      assert %{id: ^id, state: %{"playbook" => work}} =
               await_case(fn record ->
                 get_in(record.state, ["playbook", "review_attempts"]) == 1
               end)

      assert %{"review_requested" => true, "run_id" => ^run_id, "wait_id" => ^wait_id} = work
      assert {:ok, waiting} = Storage.get_run(run_id)
      assert waiting.status == :waiting

      :sys.resume(delivery)
      restart_maintenance()

      assert %{id: ^id, state: %{"phase" => "waiting_ci", "events" => events}} = await_ready()
      assert [reply] = Enum.filter(events, &(&1["actor"] == "Review"))
      assert %{"run_id" => ^run_id, "wait_id" => ^wait_id} = reply["evidence"]
      assert {:ok, finished} = Storage.get_run(run_id)
      assert Enum.count(finished.event_log, &(&1.type == :wait_resolved)) == 1
    after
      :sys.resume(delivery)
      Application.put_env(:kura, :recover_cells_on_boot, false)
    end
  end

  test "a failed case save rolls back the Loom reply and allows the same wait to retry" do
    Maintenance.subscribe()
    assert {:ok, _} = Maintenance.apply_fixture("failure_sparse")

    record = await_case(&Maintenance.fixture_review_available?/1)
    %{"run_id" => run_id, "wait_id" => wait_id} = record.state["playbook"]

    Repo.query!("""
    CREATE TEMP TRIGGER fail_review_save
    BEFORE UPDATE OF state ON maintenance_cases
    WHEN json_extract(NEW.state, '$.phase') = 'waiting_ci'
    BEGIN
      SELECT RAISE(ABORT, 'test case save failure');
    END
    """)

    try do
      assert {:ok, _} = Maintenance.apply_fixture("review_reply")

      retrying =
        await_case(fn record -> get_in(record.state, ["playbook", "review_attempts"]) == 1 end)

      assert {:ok, waiting} = Storage.get_run(run_id)
      assert [%{id: ^wait_id, status: :open}] = waiting.wait_points
      refute Enum.any?(retrying.state["events"], &(&1["actor"] == "Review"))
      refute Enum.any?(Inbox.scoped_events("cedar", record.id), &(&1.kind == "review_reply"))
    after
      Repo.query!("DROP TRIGGER IF EXISTS fail_review_save")
    end

    assert %{state: %{"phase" => "waiting_ci", "events" => events}} = await_ready()
    assert [_] = Enum.filter(events, &(&1["actor"] == "Review"))

    assert [_] =
             Enum.filter(Inbox.scoped_events("cedar", record.id), &(&1.kind == "review_reply"))

    assert {:ok, finished} = Storage.get_run(run_id)
    assert Enum.count(finished.event_log, &(&1.type == :wait_resolved)) == 1
  end

  defp await_case(predicate) do
    record = Maintenance.current()

    if record && predicate.(record) do
      record
    else
      assert_receive :maintenance_changed, 6_000
      await_case(predicate)
    end
  end

  defp restart_maintenance do
    pid = Process.whereis(Maintenance)
    assert :ok = Supervisor.terminate_child(Kura.Supervisor, Maintenance)
    assert {:ok, restarted} = Supervisor.restart_child(Kura.Supervisor, Maintenance)
    refute pid == restarted
    :sys.get_state(restarted)
  end

  defp await_ready do
    record = Maintenance.current()

    if record && record.state["phase"] != "waiting_review" && Maintenance.pending(record) == [] do
      record
    else
      assert_receive :maintenance_changed, 6_000
      await_ready()
    end
  end

  defp pulses(state) do
    for %{"evidence" => %{"pulse_id" => _} = evidence} <- state["events"], do: evidence
  end
end
