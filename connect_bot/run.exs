defmodule ConnectBot.GitHubAuth do
  alias Jido.Connect

  def connect!(agent_id, repo) do
    %{login: login, scopes: scopes} = github_session!()

    token =
      case System.cmd(
             "gh",
             ["auth", "token", "--hostname", "github.com", "--user", login],
             stderr_to_stdout: true
           ) do
        {output, 0} -> String.trim(output)
        {_, _} -> raise "Could not load the OAuth token for the active GitHub CLI account."
      end

    connection =
      Connect.Connection.new!(%{
        id: "github:#{login}",
        provider: :github,
        profile: :user,
        tenant_id: "connect-bot",
        owner_type: :app_user,
        owner_id: login,
        subject: %{login: login},
        status: :connected,
        scopes: scopes,
        metadata: %{repository: repo, agent_id: agent_id}
      })

    IO.puts("GitHub CLI authenticated as #{login}. Repository: #{repo}")
    %{connection: connection, token: token}
  end

  defp github_session! do
    args = [
      "auth",
      "status",
      "--hostname",
      "github.com",
      "--active",
      "--json",
      "hosts",
      "--jq",
      ~s(.hosts["github.com"][] | {login, state, scopes})
    ]

    with {output, 0} <- System.cmd("gh", args, stderr_to_stdout: true),
         {:ok, %{"state" => "success", "login" => login, "scopes" => scopes}}
         when is_binary(login) and is_binary(scopes) <- JSON.decode(output) do
      scopes = scopes |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

      unless "repo" in scopes do
        raise "The GitHub OAuth session needs the repo scope for Connect's user profile."
      end

      %{login: login, scopes: scopes}
    else
      _ -> raise "Run gh auth login --hostname github.com --scopes repo first."
    end
  end

  def execution_context(%{connection: connection, token: token}, agent_id) do
    %{
      integration_context:
        Connect.Context.new!(%{
          tenant_id: connection.tenant_id,
          actor: %{id: agent_id, type: :agent},
          connection: connection
        }),
      credential_lease:
        Connect.CredentialLease.from_connection!(
          connection,
          %{access_token: token, github_client: Connect.GitHub.Client},
          expires_at: DateTime.add(DateTime.utc_now(), 60, :second),
          scopes: ["repo"]
        ),
      policy: __MODULE__
    }
  end

  def authorize(
        %{id: "github.issue.list"},
        %{repo: repo, state: "open", page: 1, per_page: 30},
        %{actor: %{id: agent_id, type: :agent}},
        %{metadata: %{repository: repo, agent_id: agent_id}}
      ),
      do: :ok

  def authorize(_, _, _, _), do: {:deny, :outside_agent_binding}
end

Code.require_file("agent.exs", __DIR__)

defmodule ConnectBot.ScriptedModel do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, options) do
    messages = ReqLLM.Context.to_list(context)

    case Enum.find(messages, &(&1.role == :tool)) do
      nil ->
        [%ReqLLM.Tool{name: "github_issue_list"}] = Keyword.fetch!(options, :tools)

        %{content: [%{text: "List open issues in " <> repo}]} =
          Enum.find(messages, &(&1.role == :user))

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

defmodule ConnectBot do
  def run do
    argv = Enum.drop_while(System.argv(), &(&1 == "--"))

    {options, args, invalid} =
      OptionParser.parse(argv,
        strict: [repo: :string, live: :boolean, help: :boolean],
        aliases: [h: :help]
      )

    case {args, invalid, options[:help]} do
      {[], [], true} ->
        IO.puts("""
        Usage: connect-bot [--repo OWNER/REPO] [--live]

        Read open GitHub issues with the Jido AI agent.
        --repo defaults to elixir-lang/elixir.
        --live uses OpenAI inference and requires OPENAI_API_KEY.
        Default inference is scripted. GitHub requests are live in both modes.
        """)

      {[], [], _} ->
        read_issues(options)

      _ ->
        raise "Use connect-bot --help for usage."
    end
  end

  defp read_issues(options) do
    repo = Keyword.get(options, :repo, "elixir-lang/elixir")

    unless Regex.match?(~r/\A[a-zA-Z0-9-]+\/(?!\.\.?\z)[a-zA-Z0-9_.-]+\z/, repo) do
      raise "Use --repo OWNER/REPO and optionally --live."
    end

    agent_id = "connect-bot"
    binding = ConnectBot.GitHubAuth.connect!(agent_id, repo)

    {:ok, instance} = Jido.start_link(name: __MODULE__, namespace: "spikes/connect-bot")

    try do
      {:ok, server} = Jido.start_agent(__MODULE__, ConnectBot.Agent, id: agent_id)
      :ok = Jido.AgentServer.await_ready(server)
      IO.puts("Started #{agent_id}.")

      signal = ConnectBot.Agent.request_signal!(%{input: "List open issues in #{repo}"})

      context =
        binding
        |> ConnectBot.GitHubAuth.execution_context(agent_id)
        |> Map.put(:jido_ai_inference_client, inference_client(options))

      case Jido.AgentServer.call(server, signal, context: context, timeout: 60_000) do
        {:ok,
         %{status: :committed, reply: %{data: %{output: output, tool_calls: 1, tool_errors: 0}}}}
        when is_binary(output) and byte_size(output) > 0 ->
          IO.puts("github.issue.list succeeded.\n#{output}")

        {:ok, %{reply: %{data: %{reason: reason}}}} when is_binary(reason) ->
          raise "Agent did not finish the issue read: #{reason}"

        _ ->
          raise "Agent did not finish the issue read."
      end
    after
      Supervisor.stop(instance)
    end
  end

  defp inference_client(options) do
    if options[:live], do: Jido.AI.InferenceClient.ReqLLM, else: ConnectBot.ScriptedModel
  end
end

ConnectBot.run()
