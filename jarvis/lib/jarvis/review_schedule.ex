defmodule Jarvis.ReviewSchedule do
  @moduledoc "Defines the standing Jarvis VSM review schedule."

  alias Jido.Plugin.Timer.Occurrence
  alias Jido.Plugin.Timer

  @job_id "jarvis-review"
  @start_type "jarvis.schedule.start"
  @pause_type "jarvis.schedule.pause"
  @resume_type "jarvis.schedule.resume"

  def job_id, do: @job_id
  def start_type, do: @start_type
  def pause_type, do: @pause_type
  def resume_type, do: @resume_type

  def signal(purpose),
    do: Jido.Signal.new("jarvis.vsm.review", %{purpose: purpose}, source: "/jarvis/timer")

  def status(state) do
    case Timer.status(state, @job_id) do
      {:error, :not_found} ->
        %{status: :idle, purpose: "", interval_ms: nil, generation: nil}

      {:ok, %{kind: :every, status: status, generation: generation}} ->
        %{
          status: if(status == :active, do: :running, else: :paused),
          purpose: state.review_config.purpose,
          interval_ms: state.review_config.interval_ms,
          generation: generation
        }
    end
  end

  def accepted_generation(state, signal) do
    case Timer.status(state, @job_id) do
      {:ok, %{kind: :every, status: :active, generation: generation}} ->
        case Occurrence.from_signal(signal) do
          {:ok, %{generation: ^generation}} -> {:ok, generation}
          {:error, :not_found} -> {:ok, generation}
          _other -> :ignore
        end

      _inactive ->
        :ignore
    end
  end

  def current_generation?(state, generation) do
    match?(
      {:ok, %{kind: :every, status: :active, generation: ^generation}},
      Timer.status(state, @job_id)
    )
  end
end
