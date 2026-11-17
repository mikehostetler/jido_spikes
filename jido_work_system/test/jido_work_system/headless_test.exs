defmodule JidoWorkSystem.HeadlessTest do
  use JidoWorkSystem.DataCase, async: false

  alias JidoWorkSystem.Headless

  test "registers twelve headless-only stories" do
    stories = Simulation.headless_scenarios()

    assert length(stories) == 12
    assert Enum.all?(stories, &(&1.audience == :headless))
    assert Enum.uniq_by(stories, & &1.key) == stories
    assert length(Simulation.scenarios()) == 2
  end

  test "runs the complete story without a browser" do
    assert {:ok, trace} = Headless.run("straight-through-release")
    assert trace.status == "complete"
    assert trace.valid
    assert trace.violations == []
    assert Enum.map(trace.steps, & &1.revision) == Enum.to_list(0..10)
    assert List.last(trace.steps).event.kind == "human_accepted"
  end

  test "records the repair choice in the trace" do
    assert {:ok, trace} = Headless.run("missing-risk-section", choice: "request_revision")
    assert trace.status == "complete"
    assert trace.valid
    assert Enum.any?(trace.steps, &(&1.action == "choose:request_revision"))
    assert trace.counts.checks == 2
  end

  test "records a stopped job as a valid path" do
    assert {:ok, trace} = Headless.run("missing-risk-section", choice: "end_run")
    assert trace.status == "ended"
    assert trace.valid
    assert List.last(trace.steps).event.kind == "human_rejected"
  end

  test "all headless stories finish with valid traces" do
    traces =
      Enum.map(Simulation.headless_scenarios(), fn story ->
        assert {:ok, trace} = Headless.run(story.key)
        assert trace.valid, "#{story.key} broke a trace rule"
        assert trace.status in ["complete", "ended"]
        trace
      end)

    by_scenario = Map.new(traces, &{&1.scenario, &1})

    assert by_scenario["cell-declines-job"].counts.work == 0
    assert by_scenario["cell-declines-job"].status == "ended"

    assert List.last(by_scenario["cell-declines-job"].steps).event.kind ==
             "delegation_rejected"

    assert by_scenario["owner-cancels-work"].counts.outcomes == 0
    assert by_scenario["owner-cancels-work"].status == "ended"
    assert by_scenario["deadline-stop"].status == "ended"
    assert by_scenario["nested-specialist-cell"].counts.work == 2
    assert by_scenario["second-check-fails"].counts.checks == 2
    assert by_scenario["owner-rejects-passed-work"].counts.outcomes == 1
  end

  test "pressure runs every story and keeps traces isolated" do
    assert {:ok, report} = Headless.pressure(runs: 28)
    assert report.valid
    assert report.run_count == 28
    assert report.violation_count == 0
    assert MapSet.size(MapSet.new(report.traces, & &1.run_id)) == 28
    assert Enum.all?(report.traces, &(&1.counts.tasks == 1))

    assert Enum.sort(Enum.uniq(Enum.map(report.traces, & &1.scenario))) ==
             Enum.sort(Enum.map(Simulation.all_scenarios(), & &1.key))
  end

  test "rejects an unknown story and invalid pressure options" do
    assert {:error, :unknown_scenario} = Headless.run("unknown")
    assert {:error, :invalid_pressure_options} = Headless.pressure(runs: 0)
  end
end
