defmodule JidoWorkSystem.Simulation do
  @moduledoc """
  Public facade for deterministic work-system scenarios.

  Interactive callers create a scenario run and advance it one beat at a time.
  The legacy `run/1` function still completes a full success or rework path.
  """

  alias JidoWorkSystem.{Repo, RunSnapshot, ScenarioRunner, Scenarios, SceneProjection}

  @tables ~w(
    scenario_runs outcomes evaluations evidence mutations decisions judgments work_executions
    delegations events tasks tools knowledge workspaces judgment_methods work_cells
    accountabilities authorities roles human_actors work_systems
  )

  def scenarios, do: Scenarios.list()
  def headless_scenarios, do: Scenarios.list(:headless)
  def all_scenarios, do: Scenarios.list(:all)

  def reset do
    Repo.transaction(fn ->
      Repo.query!("PRAGMA foreign_keys = OFF")
      Enum.each(@tables, &Repo.query!("DELETE FROM #{&1}"))
      Repo.query!("PRAGMA foreign_keys = ON")
    end)

    :ok
  end

  def start_scenario(scenario_key) do
    with {:ok, run} <- ScenarioRunner.start(scenario_key) do
      {:ok, state(run)}
    end
  end

  def get_run(run_id) do
    with {:ok, run} <- ScenarioRunner.get(run_id) do
      {:ok, state(run)}
    end
  end

  def step(run_id, expected_revision) do
    with {:ok, run} <- ScenarioRunner.step(run_id, expected_revision) do
      {:ok, state(run)}
    end
  end

  def choose(run_id, expected_revision, choice) do
    with {:ok, run} <- ScenarioRunner.choose(run_id, expected_revision, choice) do
      {:ok, state(run)}
    end
  end

  def run(path \\ :success) when path in [:success, :rework] do
    scenario_key =
      case path do
        :success -> "straight-through-release"
        :rework -> "missing-risk-section"
      end

    {:ok, state} = start_scenario(scenario_key)
    complete(state, path).snapshot
  end

  def snapshot do
    case ScenarioRunner.latest() do
      {:ok, run} -> RunSnapshot.build(run)
      {:error, :not_found} -> RunSnapshot.empty()
    end
  end

  def snapshot(run_id) do
    with {:ok, run} <- ScenarioRunner.get(run_id) do
      {:ok, RunSnapshot.build(run)}
    end
  end

  def authorized?(authority, action), do: action in authority.permitted_actions

  def bounded_path?(workspace, path) do
    root = Path.expand(workspace.root)
    candidate = Path.expand(path, root)
    candidate == root or String.starts_with?(candidate, root <> "/")
  end

  defp complete(%{run: %{status: "waiting_for_choice"}} = state, :rework) do
    {:ok, next} = choose(state.run.id, state.run.revision, "request_revision")
    complete(next, :rework)
  end

  defp complete(%{run: %{status: status}} = state, _path)
       when status in ["complete", "ended"],
       do: state

  defp complete(state, path) do
    {:ok, next} = step(state.run.id, state.run.revision)
    complete(next, path)
  end

  defp state(run) do
    snapshot = RunSnapshot.build(run)
    %{run: run, snapshot: snapshot, projection: SceneProjection.build(snapshot)}
  end
end
