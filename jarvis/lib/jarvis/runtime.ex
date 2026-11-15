defmodule Jarvis.Runtime do
  @moduledoc "Public controls for the resident Timer-driven VSM review."

  alias Jarvis.ReviewSchedule

  def id, do: "jarvis-main"

  # This timer owns a resident topology. Its roles must stay available even
  # when there has been no review for longer than the chat idle timeout.
  def child_spec do
    Jido.AgentServer.child_spec(
      agent: Jarvis.Agent.instantiate!(id: id()),
      name: Jarvis.ReviewServer,
      runner: Jido.Instance.Names.exec_runner(Jarvis.Jido)
    )
  end

  def server do
    case Process.whereis(Jarvis.ReviewServer) do
      nil -> {:error, :review_server_unavailable}
      pid -> with :ok <- Jido.AgentServer.await_ready(pid), do: {:ok, pid}
    end
  end

  def start(purpose, opts \\ []) do
    purpose = String.trim(purpose)

    if purpose == "" do
      {:error, Jido.Error.validation_error("A purpose is required")}
    else
      call(ReviewSchedule.start_type(), %{
        purpose: purpose,
        chat_topic: opts[:chat_topic] || "",
        interval_ms: Keyword.get(opts, :interval_ms, 30_000)
      })
    end
  end

  def pause, do: call(ReviewSchedule.pause_type(), %{})
  def resume, do: call(ReviewSchedule.resume_type(), %{})

  def status do
    with {:ok, server} <- server() do
      %{agent: %{state: state}} = Jido.AgentServer.snapshot(server)
      schedule = ReviewSchedule.status(state)

      {:ok,
       state
       |> Map.take([:reviews, :last_review])
       |> Map.put(:schedule, schedule)
       |> Map.put(:model, Jarvis.model())}
    end
  end

  def call(type, data) do
    with {:ok, server} <- server(),
         {:ok, signal} <- Jido.Signal.new(type, data, source: "/jarvis/client") do
      case Jido.AgentServer.call(server, signal, 5000) do
        {:ok, %{status: :committed, reply: %{data: response}}} ->
          {:ok, response}

        {:ok, result} ->
          {:error,
           Jido.Error.execution_error("Jarvis did not accept the request",
             details: %{status: result.status}
           )}

        {:error, _reason} = error ->
          error
      end
    end
  end
end
