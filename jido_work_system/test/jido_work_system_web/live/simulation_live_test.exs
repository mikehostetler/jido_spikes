defmodule JidoWorkSystemWeb.SimulationLiveTest do
  use JidoWorkSystemWeb.ConnCase, async: false

  alias JidoWorkSystem.Simulation

  test "lists scenarios and starts a selected run", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#scenario-catalog")
    assert has_element?(view, "#scenario-straight-through-release")
    assert has_element?(view, "#scenario-missing-risk-section")

    view |> element("#start-straight-through-release") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r|/runs/[0-9a-f-]+|
  end

  test "steps a run and opens its matching debug view", %{conn: conn} do
    {:ok, state} = Simulation.start_scenario("straight-through-release")
    {:ok, view, _html} = live(conn, "/runs/#{state.run.id}")

    assert has_element?(view, "#simulation-player")
    assert has_element?(view, "#scenario-stage[phx-hook='ScenarioStage'][phx-update='ignore']")
    assert has_element?(view, "#transport-controls")
    assert has_element?(view, "#debug-link")

    view |> element("#step") |> render_click()
    assert has_element?(view, "#narration", "Mike has a job to do")

    {:ok, debug_view, _html} = live(conn, "/runs/#{state.run.id}/debug")
    assert has_element?(debug_view, "#simulation-debug")
    assert has_element?(debug_view, "#event-1[data-kind='task_defined']")
  end

  test "play advances only after the current animation acknowledgement", %{conn: conn} do
    {:ok, state} = Simulation.start_scenario("straight-through-release")
    {:ok, view, _html} = live(conn, "/runs/#{state.run.id}")

    view |> element("#play") |> render_click()
    assert has_element?(view, "#player-mode", "playing")

    render_hook(view, "animation_complete", %{
      "run_id" => state.run.id,
      "revision" => 1
    })

    {:ok, advanced} = Simulation.get_run(state.run.id)
    assert advanced.run.revision == 2

    render_hook(view, "animation_complete", %{
      "run_id" => state.run.id,
      "revision" => 1
    })

    {:ok, unchanged} = Simulation.get_run(state.run.id)
    assert unchanged.run.revision == 2

    view |> element("#pause") |> render_click()
    assert has_element?(view, "#player-mode", "paused")
  end

  test "stops for the missing-risk human decision", %{conn: conn} do
    {:ok, state} = Simulation.start_scenario("missing-risk-section")
    {:ok, view, _html} = live(conn, "/runs/#{state.run.id}")

    Enum.each(1..9, fn _index -> view |> element("#step") |> render_click() end)

    assert has_element?(view, "#decision-panel")
    assert has_element?(view, "#choice-request_revision")
    assert has_element?(view, "#choice-end_run")
    assert has_element?(view, "#player-mode", "paused")

    view |> element("#choice-request_revision") |> render_click()
    refute has_element?(view, "#decision-panel")

    {:ok, revised} = Simulation.get_run(state.run.id)
    assert List.last(revised.snapshot.events).kind == "rework_requested"
  end

  test "shows a controlled not-found state", %{conn: conn} do
    missing_id = Ecto.UUID.generate()

    {:ok, player, _html} = live(conn, "/runs/#{missing_id}")
    assert has_element?(player, "#run-not-found")

    {:ok, debug, _html} = live(conn, "/runs/#{missing_id}/debug")
    assert has_element?(debug, "#debug-not-found")
  end

  test "pauses and keeps HTML controls when the stage fails", %{conn: conn} do
    {:ok, state} = Simulation.start_scenario("straight-through-release")
    {:ok, view, _html} = live(conn, "/runs/#{state.run.id}")

    view |> element("#play") |> render_click()
    render_hook(view, "stage_failed", %{})

    assert has_element?(view, "#player-mode", "paused")
    assert has_element?(view, "#simulation-error", "The picture could not start")
    assert has_element?(view, "#step")
    assert has_element?(view, "#debug-link")
  end
end
