defmodule JarvisWeb.AliceLiveTest do
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    previous_client = Application.get_env(:jido, :ai_inference_client)

    Application.put_env(:jido, :ai_inference_client, Jarvis.TestInferenceClient)
    Application.put_env(:jarvis, :test_inference_owner, self())
    Application.put_env(:jarvis, :test_stream_delay_ms, 0)

    Application.put_env(
      :jarvis,
      :test_inference_result,
      {:ok,
       JSON.encode!(%{
         "narrative" => "The signal is now bounded by one verified observation.",
         "next_state" => %{
           "situation" => "A refined bounded situation is under review.",
           "focus" => "Test the signal against known evidence.",
           "evidence" => ["The first observation is present."],
           "tensions" => ["The source remains unknown."],
           "intention" => "Compare the signal with one trusted baseline.",
           "tool_need" => ""
         },
         "memories" => ["The first observation remains relevant."],
         "next_wake" => "continue"
       })}
    )

    on_exit(fn ->
      Application.delete_env(:jarvis, :test_inference_owner)
      Application.delete_env(:jarvis, :test_inference_result)
      Application.delete_env(:jarvis, :test_stream_delay_ms)

      if previous_client do
        Application.put_env(:jido, :ai_inference_client, previous_client)
      else
        Application.delete_env(:jido, :ai_inference_client)
      end
    end)

    :ok
  end

  test "step mode advances one cognitive cycle and shows the exact model input", %{conn: conn} do
    {:ok, view, html} = live(conn, "/alice")

    assert html =~ "Stable identity kernel"
    assert has_element?(view, "#alice-character-kernel")
    assert has_element?(view, "#alice-character-prompt", "# Character: Alice")
    assert has_element?(view, "#alice-character-prompt", "call sign Major")
    assert has_element?(view, "#alice-character-version", "version 1")

    view
    |> form("#alice-form",
      alice: %{
        run_directive: "Keep facts exact.",
        thought: "Assess the first idea.",
        mode: "step",
        turn_limit: "3"
      }
    )
    |> render_submit()

    refute_received {:model_request, _model, _context}
    assert has_element?(view, "#alice-next")

    view |> element("#alice-next") |> render_click()

    assert has_element?(view, "#alice-turn-list article")
    assert_receive {:model_request, model, context}, 5_000
    assert inspect(model) =~ "lfm3-1.7b"
    assert context_text(context) =~ "Assess the first idea."

    assert eventually(fn ->
             has_element?(view, "#alice-context-out-1", "A refined bounded situation")
           end)

    assert has_element?(view, "#alice-model-input-1", "[SYSTEM]")
    assert has_element?(view, "#alice-model-input-1", "# Cognitive pulse 1")
    assert has_element?(view, "#alice-model-input-1", "# Character: Alice")
    assert has_element?(view, "#alice-model-input-1", "## Run directive")
    assert has_element?(view, "#alice-current-context", "A refined bounded situation")
    assert has_element?(view, "#alice-progress", "1 / 3 · step")
  end

  test "a cycle card appears before completion and receives live token chunks", %{conn: conn} do
    Application.put_env(:jarvis, :test_stream_delay_ms, 40)
    {:ok, view, _html} = live(conn, "/alice")

    view
    |> form("#alice-form",
      alice: %{
        run_directive: "Maintain continuity.",
        thought: "Notice the strongest signal.",
        mode: "step",
        turn_limit: "2"
      }
    )
    |> render_submit()

    view |> element("#alice-next") |> render_click()

    assert has_element?(view, "#alice-stream-output-1")

    assert eventually(fn ->
             has_element?(view, "#alice-stream-output-1", "narrative")
           end)

    assert eventually(fn ->
             has_element?(view, "#alice-context-out-1", "A refined bounded situation")
           end)
  end

  test "automatic mode runs to its cycle limit even when a proposal asks to wait", %{conn: conn} do
    {:ok, {:ok, proposal_json}} = Application.fetch_env(:jarvis, :test_inference_result)

    waiting_proposal =
      proposal_json
      |> JSON.decode!()
      |> Map.put("next_wake", "wait")
      |> JSON.encode!()

    Application.put_env(:jarvis, :test_inference_result, {:ok, waiting_proposal})

    {:ok, view, _html} = live(conn, "/alice")

    view
    |> form("#alice-form",
      alice: %{
        run_directive: "Refine the plan.",
        thought: "Start with one plan.",
        mode: "automatic",
        turn_limit: "2"
      }
    )
    |> render_submit()

    assert_receive {:model_request, _model, first_context}, 5_000
    assert_receive {:model_request, _model, second_context}, 5_000

    assert context_text(first_context) =~ "Start with one plan."
    assert context_text(second_context) =~ "A refined bounded situation is under review."
    refute context_text(second_context) =~ "Pending tool need:\nNone\n\nPending tool need:"

    assert eventually(fn -> has_element?(view, "#alice-context-out-2") end)
    assert eventually(fn -> has_element?(view, "#alice-operation", "complete") end)
    assert has_element?(view, "#current-context-title", "Final ghost-state")
    assert has_element?(view, "#alice-progress", "2 / 2 · automatic")
  end

  defp eventually(fun, attempts \\ 300)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      receive do
      after
        10 -> eventually(fun, attempts - 1)
      end
    end
  end

  defp context_text(context) do
    context
    |> ReqLLM.Context.to_list()
    |> Enum.flat_map(& &1.content)
    |> Enum.map_join("\n", & &1.text)
  end
end
