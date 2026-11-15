defmodule Jarvis.Actions.Schedule do
  @moduledoc "Controls the standing VSM review through Jido Timer."

  use Jido.Action,
    name: "jarvis_schedule_reviews",
    schema:
      Jido.Joi.object(%{
        command: Jido.Joi.enum([:start, :pause, :resume]),
        purpose: Jido.Joi.string() |> Jido.Joi.max(8_000) |> Jido.Joi.default(""),
        chat_topic: Jido.Joi.string() |> Jido.Joi.default(""),
        interval_ms:
          Jido.Joi.integer()
          |> Jido.Joi.min(1)
          |> Jido.Joi.max(4_294_967_295)
          |> Jido.Joi.default(30_000)
      }),
    output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), reply: Jido.Joi.map()})

  alias Jarvis.ReviewSchedule
  alias Jido.Plugin.Timer

  @impl true
  def run(
        %{command: :start, purpose: purpose} = input,
        context
      ) do
    purpose = String.trim(purpose)

    if purpose == "" do
      {:error, Jido.Error.validation_error("A purpose is required")}
    else
      with {:ok, signal} <- ReviewSchedule.signal(purpose) do
        effects = [
          Timer.every(ReviewSchedule.job_id(), input.interval_ms, signal),
          Jarvis.Signals.emit(context, "jarvis.vsm.review", %{purpose: purpose})
        ]

        config = %{
          purpose: purpose,
          interval_ms: input.interval_ms,
          chat_topic: input.chat_topic,
          review_id: Ecto.UUID.generate()
        }

        reply(Map.put(context.agent_state, :review_config, config), :running, config, effects)
      end
    end
  end

  def run(%{command: command}, %{agent_state: state} = context)
      when command in [:pause, :resume] do
    schedule = ReviewSchedule.status(state)

    case {command, schedule.status} do
      {:pause, :running} ->
        reply(state, :paused, schedule, [
          Timer.pause(ReviewSchedule.job_id())
        ])

      {:resume, :paused} ->
        reply(state, :running, schedule, [
          Timer.resume(ReviewSchedule.job_id()),
          Jarvis.Signals.emit(context, "jarvis.vsm.review", %{purpose: schedule.purpose})
        ])

      _ ->
        {:ok, %{state: state, reply: Map.put(schedule, :ignored, true)}}
    end
  end

  defp reply(state, status, config, effects) do
    response = %{
      status: status,
      purpose: config.purpose,
      interval_ms: config.interval_ms,
      ignored: false
    }

    {:ok, %{state: state, reply: response}, effects}
  end
end
