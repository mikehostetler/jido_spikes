defmodule ConnectBot.ScriptedModel do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, options) do
    {turn_messages, [request | _history]} =
      context
      |> ReqLLM.Context.to_list()
      |> Enum.reverse()
      |> Enum.split_while(&(&1.role != :user))

    case Enum.find(turn_messages, &(&1.role == :tool)) do
      nil ->
        [%ReqLLM.Tool{name: "github_issue_list"}] = Keyword.fetch!(options, :tools)

        %{content: [%{text: "List open issues in " <> repo}]} = request

        arguments = JSON.encode!(%{repo: repo, state: "open", page: 1, per_page: 30})
        call = ReqLLM.ToolCall.new("read-issues", "github_issue_list", arguments)
        reply(model, context, ReqLLM.Context.assistant("", tool_calls: [call]), :tool_calls)

      %{content: [%{text: text}]} ->
        with {:ok, %{"issues" => issues}} <- JSON.decode(text) do
          issues = issues |> Enum.reject(&Map.has_key?(&1, "pull_request")) |> Enum.take(5)
          answer = Enum.map_join(issues, "\n", &"##{&1["number"]} #{&1["title"]}")
          answer = if issues == [], do: "No open issues in the returned page.", else: answer
          reply(model, context, ReqLLM.Context.assistant(answer), :stop)
        else
          _ -> {:error, :github_read_failed}
        end
    end
  end

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      {name, arity} != {:generate_text, 3} do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
      do: {:error, :not_supported}
  end

  defp reply(model, context, message, finish_reason) do
    {:ok,
     %ReqLLM.Response{
       id: "connect-bot",
       model: model,
       context: context,
       message: message,
       finish_reason: finish_reason,
       usage: %{input_tokens: 0, output_tokens: 0}
     }}
  end
end
