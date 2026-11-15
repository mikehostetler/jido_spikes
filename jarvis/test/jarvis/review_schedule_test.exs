defmodule Jarvis.ReviewScheduleTest do
  use ExUnit.Case, async: true

  alias Jarvis.ReviewSchedule
  alias Jido.Plugin.Timer

  test "only the current running generation can review the purpose" do
    purpose = "review current evidence"
    {:ok, template} = ReviewSchedule.signal(purpose)

    timer = %{
      every: %{
        ReviewSchedule.job_id() => %{
          interval_ms: 1_000,
          message: template,
          generation: 2,
          status: :running
        }
      },
      cron: %{}
    }

    scope = {Jarvis.Jido, Jarvis.Runtime.id(), nil}
    now = DateTime.utc_now()

    assert {:ok, current} =
             Timer.occurrence_signal(template, scope, ReviewSchedule.job_id(), 2, now)

    assert {:ok, stale} =
             Timer.occurrence_signal(template, scope, ReviewSchedule.job_id(), 1, now)

    state = %{timer: timer}
    assert {:ok, 2} = ReviewSchedule.accepted_generation(state, current)
    assert :ignore = ReviewSchedule.accepted_generation(state, stale)
    assert ReviewSchedule.current_generation?(state, 2)
    refute ReviewSchedule.current_generation?(state, 1)

    paused = put_in(state, [:timer, :every, ReviewSchedule.job_id(), :status], :paused)
    assert :ignore = ReviewSchedule.accepted_generation(paused, current)
    refute ReviewSchedule.current_generation?(paused, 2)
  end
end
