defmodule KuraWeb.MaintenanceLiveTest do
  use KuraWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Kura.{Maintenance, Playbooks}
  alias Kura.Cell.Inbox
  alias Kura.Playbooks.{Storage, Triage}

  test "Cedar learns from saved pulses and replays the approved HTN on a later turn", %{
    conn: conn
  } do
    Maintenance.subscribe()
    assert {:ok, view, _html} = live(conn, ~p"/maintenance")

    click_next(view)

    first =
      await_case(fn record ->
        record.state["phase"] == "waiting_ci" and Maintenance.pending(record) == []
      end)

    assert [ci, review] = Inbox.scoped_events("cedar", first.id)
    assert ci.kind == "ci_snapshot" and review.kind == "review_reply"

    for _step <- 1..3 do
      click_next(view)
      await_case(&(Maintenance.pending(&1) == []))
    end

    assert %{id: source_case, state: %{"phase" => "closed"}} = Maintenance.current()
    assert source_case == first.id
    closure = List.last(Inbox.scoped_events("cedar", source_case))
    assert closure.kind == "case_closed"

    assert %{
             "observations" => %{"ci_pulse_id" => ci_id, "review_pulse_id" => review_id},
             "scores" => %{"baseline" => 0.5, "guarded" => 1.0}
           } = closure.trace["learning"]

    assert ci_id == ci.id and review_id == review.id
    assert {:ok, draft} = Playbooks.get("cedar", closure.id)
    assert draft.document["type"] == "jido.htn.domain"
    assert draft.replay["passed"]
    refute draft.approved
    assert has_element?(view, "[data-tune-learning='#{closure.id}']")
    assert render(view) =~ "Replay passed"

    view |> element("button[phx-click=approve_candidate]") |> render_click()
    render_async(view, 5_000)
    assert Playbooks.active("cedar", "ci_triage").id == draft.id

    click_next(view)

    later =
      await_case(fn record -> record.id != source_case and Maintenance.pending(record) == [] end)

    assert later.state["phase"] == "waiting_ci"
    assert [turn] = Inbox.scoped_events("cedar", later.id)
    assert {:ok, run} = Storage.get_run(turn.id)
    assert run.playbook_ref.playbook_id == draft.id
    assert run.status == :succeeded
    assert run.wait_points == []
    assert [%{method_name: "use_ci_evidence"}] = run.method_selections

    assert has_element?(view, "[data-tune-learning='#{closure.id}']")
    assert has_element?(view, "#cedar-learned-replay[data-replay-pulse='#{turn.id}']")
    assert render(view) =~ "Use CI evidence · Playbook v2"
  end

  test "Cedar assigns ten cases to three workers and recovers a queued case", %{conn: conn} do
    Maintenance.subscribe()
    {:ok, baseline} = Triage.seed()

    {:ok, draft} =
      Playbooks.proposal(baseline, Ash.UUID.generate(), %{}, %{
        "method" => "ask_review",
        "condition" => "missing_assertion"
      })

    assert {:ok, _} = Playbooks.replay("cedar", draft.id)
    assert {:ok, _} = Playbooks.approve("cedar", draft.id)

    assert {:ok, view, _} = live(conn, ~p"/maintenance")
    view |> element("#open-maintenance-pool") |> render_click()
    render_async(view, 10_000)

    cases =
      await_portfolio(fn cases ->
        length(cases) == 10 and Enum.all?(cases, &(Maintenance.pending(&1) == []))
      end)

    assert Enum.map(Maintenance.workers(), fn worker ->
             Enum.count(cases, &(Maintenance.worker_id(&1) == worker))
           end) == [4, 3, 3]

    assert length(Enum.uniq_by(cases, & &1.state["original_head"])) == 10

    assert Enum.map(Enum.take(cases, 3), & &1.state["phase"]) ==
             List.duplicate("waiting_review", 3)

    assert Enum.all?(Enum.drop(cases, 3), &(&1.state["phase"] == "waiting_ci"))
    assert has_element?(view, "#portfolio-count", "10 open · 10 total")
    assert {:error, :pool_already_open} = Maintenance.open_pool()

    [waiting, _, _, advancing | _] = cases
    assert Maintenance.worker_id(waiting) == Maintenance.worker_id(advancing)
    waiting_run = waiting.state["playbook"]["run_id"]
    wait_id = waiting.state["playbook"]["wait_id"]
    complete_run = advancing.state["playbook"]["run_id"]

    assert {:ok, %{status: :succeeded, playbook_ref: %{playbook_id: version}}} =
             Storage.get_run(complete_run)

    assert version == draft.id

    render_patch(view, ~p"/maintenance?case=#{advancing.id}")
    assert has_element?(view, "#case-title", "Case 4")

    [{worker, _}] = Registry.lookup(Kura.Cell.Registry, Maintenance.worker_id(advancing))
    :sys.suspend(worker)
    assert {:ok, advanced} = Maintenance.apply_fixture("new_head", advancing.id)
    assert [%{"type" => "ci_snapshot"}] = Maintenance.pending(advanced)
    assert :ok = DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, worker)
    assert :ok = Supervisor.terminate_child(Kura.Supervisor, Maintenance)

    Application.put_env(:kura, :recover_cells_on_boot, true)

    try do
      assert {:ok, _} = Supervisor.restart_child(Kura.Supervisor, Maintenance)

      await_portfolio(fn cases ->
        Enum.any?(cases, &(&1.id == advancing.id and Maintenance.pending(&1) == []))
      end)
    after
      Application.put_env(:kura, :recover_cells_on_boot, false)
    end

    assert {:ok, stale} = Maintenance.apply_fixture("stale_pass", advancing.id)
    assert stale.state["phase"] == "waiting_ci"

    await_portfolio(fn cases ->
      Enum.any?(cases, &(&1.id == advancing.id and Maintenance.pending(&1) == []))
    end)

    assert {:ok, closed} = Maintenance.apply_fixture("pass", advancing.id)
    assert closed.state["phase"] == "closed"

    await_portfolio(fn cases ->
      Enum.all?(cases, &(Maintenance.pending(&1) == []))
    end)

    assert Maintenance.fetch(waiting.id).state["phase"] == "waiting_review"

    assert {:ok, %{status: :waiting, wait_points: [%{id: ^wait_id}]}} =
             Storage.get_run(waiting_run)

    assert has_element?(view, "#portfolio-count", "9 open · 10 total")
  end

  defp click_next(view) do
    view |> element("#maintenance-next") |> render_click()
    render_async(view, 5_000)
  end

  defp await_portfolio(predicate) do
    cases = Maintenance.portfolio()

    if predicate.(cases) do
      cases
    else
      assert_receive :maintenance_changed, 10_000
      await_portfolio(predicate)
    end
  end

  defp await_case(predicate) do
    record = Maintenance.current()

    if record && predicate.(record) do
      record
    else
      assert_receive :maintenance_changed, 5_000
      await_case(predicate)
    end
  end
end
