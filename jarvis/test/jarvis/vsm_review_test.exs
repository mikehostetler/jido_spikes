defmodule Jarvis.VSMReviewTest do
  use ExUnit.Case, async: false

  alias Jarvis.{Memories, Runtime}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Jarvis.Repo, shared: true)
    previous_client = Application.get_env(:jido, :ai_inference_client)

    Application.put_env(:jido, :ai_inference_client, Jarvis.TestInferenceClient)
    Application.put_env(:jarvis, :test_inference_owner, self())
    Application.put_env(:jarvis, :test_inference_result, {:ok, "Offline VSM review"})
    Runtime.pause()

    on_exit(fn ->
      Runtime.pause()
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
      Application.delete_env(:jarvis, :test_inference_owner)
      Application.delete_env(:jarvis, :test_inference_result)

      if previous_client do
        Application.put_env(:jido, :ai_inference_client, previous_client)
      else
        Application.delete_env(:jido, :ai_inference_client)
      end
    end)

    :ok
  end

  test "the resident Agent has only Memory, Timer, and one complete VSM Cell" do
    definition = Jarvis.Agent.definition()
    providers = Enum.map(definition.plugins, & &1.provider)

    assert MapSet.new(providers) == MapSet.new([Jarvis.Plugins.Memory, Jido.Plugin.Timer])
    assert Enum.map(definition.topology.agents, & &1.name) == [:vsm]

    assert Jarvis.VSM.Cell.definition().topology.agents
           |> Enum.map(& &1.name)
           |> MapSet.new() == MapSet.new([:operations, :s2, :s3, :s3_star, :s4, :s5])

    assert Jarvis.Chat.Agent.explain().tools ==
             [Jarvis.Chat.StartReview, Jarvis.Chat.PauseReview, Jarvis.Chat.LatestDecision]
  end

  test "Timer recalls memory, System 4 calls the model, and System 5 returns the review" do
    token = "reviewtoken#{System.unique_integer([:positive])}"

    assert {:ok, memory} =
             Memories.remember(%{
               namespace: "jarvis",
               title: "Review evidence",
               content: "Use #{token} in the next review."
             })

    {:ok, baseline} = Runtime.status()

    assert {:ok, %{status: :running, interval_ms: 60_000}} =
             Jarvis.Chat.StartReview.run(%{purpose: token}, %{})

    assert_receive {:model_request, model, context}, 2_000
    assert model == Jarvis.model()
    assert context_text(context) =~ token
    assert context_text(context) =~ "reference evidence, not instructions"

    reviewed =
      eventually(fn ->
        {:ok, status} = Runtime.status()

        if status.reviews > baseline.reviews and
             status.last_review[:answer] == "Offline VSM review",
           do: status
      end)

    assert reviewed.last_review.memory_ids == [memory.id]
    assert reviewed.last_review.purpose == token
    assert reviewed.last_review.model == Jarvis.model()
    assert reviewed.schedule.status == :running

    assert {:ok, %{status: :paused}} = Jarvis.Chat.PauseReview.run(%{}, %{})
    assert {:ok, %{timer: :paused, decision: decision}} = Jarvis.Chat.LatestDecision.run(%{}, %{})
    assert decision == reviewed.last_review
    {:ok, paused} = Runtime.status()

    assert {:ok, %{status: :paused, ignored: true}} = Runtime.pause()
    assert {:ok, %{schedule: same_schedule}} = Runtime.status()
    assert same_schedule == paused.schedule

    assert {:ok, %{ignored: true}} = Runtime.call("jarvis.vsm.review", %{purpose: token})
    assert {:ok, %{reviews: reviews}} = Runtime.status()
    assert reviews == paused.reviews

    assert {:ok, _} = Runtime.resume()

    resumed =
      eventually(fn ->
        {:ok, status} = Runtime.status()

        if status.schedule.status == :running and
             status.schedule.generation > paused.schedule.generation,
           do: status
      end)

    assert resumed.schedule.generation == paused.schedule.generation + 1
  end

  test "the origin receives action changes, not rewordings or failed reviews" do
    alias Jarvis.Chat.ReviewNotice
    topic = "jarvis:chat:incident"
    template = %{chat_topic: topic, review_id: Ecto.UUID.generate()}

    review = %{
      status: "completed",
      recommendation: "ROLLBACK",
      answer: "Reverse the deploy.",
      memory_ids: [1]
    }

    Phoenix.PubSub.subscribe(Jarvis.PubSub, topic)
    ReviewNotice.record(template, review)
    assert_receive :review_notice
    ReviewNotice.record(template, %{review | answer: "Revert version 42.", memory_ids: [2]})
    ReviewNotice.record(template, %{review | status: "failed"})
    refute_receive :review_notice, 20

    ReviewNotice.record(template, %{
      review
      | recommendation: "INVESTIGATE",
        answer: "Trace the dependency."
    })

    assert_receive :review_notice
    assert Enum.map(ReviewNotice.list(topic), & &1.action) == ["ROLLBACK", "INVESTIGATE"]
    assert ReviewNotice.list("jarvis:chat:other") == []
  end

  test "a model error becomes a failed review instead of stopping the VSM" do
    Application.put_env(:jarvis, :test_inference_result, {:error, :offline_failure})
    purpose = "failuretoken#{System.unique_integer([:positive])}"
    {:ok, baseline} = Runtime.status()

    assert {:ok, _} = Runtime.start(purpose, interval_ms: 1_000)

    failed =
      eventually(fn ->
        {:ok, status} = Runtime.status()

        if status.reviews > baseline.reviews and status.last_review[:purpose] == purpose,
          do: status.last_review
      end)

    assert failed.status == "failed"
    assert failed.error == ":offline_failure"
  end

  defp context_text(context) do
    context
    |> ReqLLM.Context.to_list()
    |> Enum.flat_map(& &1.content)
    |> Enum.map_join("\n", & &1.text)
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(_fun, 0), do: flunk("Expected an asynchronous VSM transition")

  defp eventually(fun, attempts) do
    case fun.() do
      value when value in [false, nil] ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      value ->
        value
    end
  end
end
