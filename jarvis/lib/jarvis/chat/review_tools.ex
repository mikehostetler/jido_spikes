defmodule Jarvis.Chat.StartReview do
  use Jido.Action,
    name: "start_review",
    description:
      "Start or replace the shared VSM review timer. Reviews the purpose immediately and every minute.",
    schema:
      Jido.Joi.object(%{purpose: Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.max(8_000)})

  @impl true
  def run(%{purpose: purpose}, context),
    do:
      Jarvis.Runtime.start(purpose, interval_ms: 60_000, chat_topic: context[:jarvis_chat_topic])
end

defmodule Jarvis.Chat.PauseReview do
  use Jido.Action,
    name: "pause_review",
    description: "Pause the shared recurring VSM review timer. Keep the last recorded decision.",
    schema: Jido.Joi.object(%{})

  @impl true
  def run(_input, _context), do: Jarvis.Runtime.pause()
end

defmodule Jarvis.Chat.LatestDecision do
  use Jido.Action,
    name: "latest_decision",
    description:
      "Read the shared timer status and the latest recorded VSM decision with its evidence IDs.",
    schema: Jido.Joi.object(%{})

  @impl true
  def run(_input, _context) do
    with {:ok, %{schedule: schedule, last_review: review}} <- Jarvis.Runtime.status() do
      decision =
        cond do
          schedule.status == :running and review[:generation] != schedule.generation ->
            %{status: :pending}

          review == %{} ->
            %{status: :none}

          true ->
            review
        end

      {:ok, %{timer: schedule.status, purpose: schedule.purpose, decision: decision}}
    end
  end
end
