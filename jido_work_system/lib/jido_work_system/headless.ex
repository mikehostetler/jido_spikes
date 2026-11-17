defmodule JidoWorkSystem.Headless do
  @moduledoc """
  Runs work stories without a browser and returns JSON-safe traces.
  """

  alias JidoWorkSystem.{Scenarios, Simulation, TraceRules}

  @default_max_steps 100

  def run(scenario_key, opts \\ []) do
    choice = Keyword.get(opts, :choice, "request_revision")
    max_steps = Keyword.get(opts, :max_steps, @default_max_steps)

    with {:ok, state} <- Simulation.start_scenario(scenario_key) do
      initial = trace_step(state, "start")
      advance(state, choice, max_steps, [initial])
    end
  end

  def pressure(opts \\ []) do
    run_count = Keyword.get(opts, :runs, 100)
    scenario_keys = Keyword.get(opts, :scenarios, Enum.map(Scenarios.list(:all), & &1.key))

    if run_count < 1 or scenario_keys == [] do
      {:error, :invalid_pressure_options}
    else
      started_at = System.monotonic_time()

      traces =
        1..run_count
        |> Enum.map(fn index ->
          scenario_key = Enum.at(scenario_keys, rem(index - 1, length(scenario_keys)))
          choice = pressure_choice(scenario_key, index)
          {:ok, trace} = run(scenario_key, choice: choice)
          trace
        end)

      elapsed_us =
        (System.monotonic_time() - started_at)
        |> System.convert_time_unit(:native, :microsecond)

      violations = Enum.flat_map(traces, & &1.violations)

      {:ok,
       %{
         schema_version: 1,
         run_count: run_count,
         scenario_count: length(scenario_keys),
         step_count: Enum.sum(Enum.map(traces, &length(&1.steps))),
         elapsed_ms: Float.round(elapsed_us / 1000, 3),
         valid: violations == [],
         violation_count: length(violations),
         run_statuses: Enum.frequencies_by(traces, & &1.status),
         final_events:
           Enum.frequencies_by(traces, &get_in(&1, [:steps, Access.at(-1), :event, :kind])),
         traces: traces
       }}
    end
  end

  defp advance(state, _choice, steps_left, trace_steps)
       when state.run.status in ["complete", "ended"] do
    {:ok, finish_trace(state, trace_steps, steps_left)}
  end

  defp advance(state, _choice, 0, trace_steps) do
    step = trace_step(state, "step_limit")
    problem = %{code: "step_limit", message: "The story did not finish before the step limit."}

    {:ok,
     finish_trace(state, trace_steps ++ [%{step | violations: step.violations ++ [problem]}], 0)}
  end

  defp advance(%{run: %{status: "waiting_for_choice"}} = state, choice, steps_left, trace_steps) do
    case Simulation.choose(state.run.id, state.run.revision, choice) do
      {:ok, next} ->
        advance(
          next,
          choice,
          steps_left - 1,
          trace_steps ++ [trace_step(next, "choose:#{choice}")]
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp advance(state, choice, steps_left, trace_steps) do
    case Simulation.step(state.run.id, state.run.revision) do
      {:ok, next} ->
        advance(next, choice, steps_left - 1, trace_steps ++ [trace_step(next, "step")])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finish_trace(state, steps, _steps_left) do
    violations =
      steps
      |> Enum.flat_map(fn step ->
        Enum.map(step.violations, &Map.put(&1, :revision, step.revision))
      end)

    %{
      schema_version: 1,
      run_id: state.run.id,
      scenario: state.run.scenario_key,
      status: state.run.status,
      valid: violations == [],
      violations: violations,
      counts: counts(state.snapshot),
      steps: steps
    }
  end

  defp trace_step(state, action) do
    event = List.last(state.snapshot.events)

    %{
      revision: state.run.revision,
      cursor: state.run.cursor,
      status: state.run.status,
      beat: state.run.current_beat,
      action: action,
      narration: state.projection.narration,
      event: event_map(event),
      counts: counts(state.snapshot),
      violations: TraceRules.check(state.snapshot)
    }
  end

  defp event_map(nil), do: nil

  defp event_map(event) do
    %{sequence: event.sequence, kind: event.kind, summary: event.summary, data: event.data}
  end

  defp counts(snapshot) do
    %{
      tasks: length(snapshot.tasks),
      delegations: length(snapshot.delegations),
      work: length(snapshot.work),
      judgments: length(snapshot.judgments),
      changes: length(snapshot.mutations),
      evidence: length(snapshot.evidence),
      checks: length(snapshot.evaluations),
      outcomes: length(snapshot.outcomes),
      events: length(snapshot.events)
    }
  end

  defp pressure_choice("missing-risk-section", index) when rem(index, 4) == 0, do: "end_run"
  defp pressure_choice(_scenario_key, _index), do: "request_revision"
end
