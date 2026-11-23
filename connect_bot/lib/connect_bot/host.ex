defmodule ConnectBot.Host do
  alias ConnectBot.{IssueAgent, Store}
  alias Jido.Connect.{Context, CredentialLease, Error}

  def agent_id(owner, slot), do: "#{owner}:#{slot}"

  def read(owner, slot, requested_repo \\ nil) do
    with {:ok, binding} <- lookup(owner, slot) do
      run_turn(agent_id(owner, slot), requested_repo || binding.repo, turn_context(binding))
    end
  end

  def run_turn(agent_id, repo, context) do
    with {:ok, server} <- start_agent(agent_id),
         :ok <- Jido.AgentServer.await_ready(server) do
      signal = IssueAgent.request_signal!(%{input: "List open issues in #{repo}"})

      case Jido.AgentServer.call(server, signal, context: context, timeout: 60_000) do
        {:ok,
         %{status: :committed, reply: %{data: %{output: output, tool_calls: 1, tool_errors: 0}}}}
        when is_binary(output) and byte_size(output) > 0 ->
          {:ok, output}

        _ ->
          {:error, :issue_read_failed}
      end
    end
  end

  def turn_context(binding) do
    %{
      integration_context:
        Context.new!(%{
          tenant_id: binding.owner,
          actor: %{type: :agent, id: agent_id(binding.owner, binding.slot)},
          connection: binding.connection,
          metadata: %{binding_ref: binding.ref}
        }),
      credential_resolver: __MODULE__,
      policy: __MODULE__,
      jido_ai_inference_client:
        Application.get_env(:connect_bot, :inference_client, ConnectBot.ScriptedModel)
    }
  end

  def resolve_lease(
        %{
          tenant_id: owner,
          actor: %{id: agent_id},
          metadata: %{binding_ref: ref},
          connection: conn
        },
        "github.issue.list",
        %{repo: repo, state: "open", page: 1, per_page: 30}
      ) do
    case Store.authorized_token(owner, agent_id, ref, conn.id, repo) do
      {:ok, token, expires_at} ->
        max_expiry = DateTime.add(DateTime.utc_now(), 60, :second)

        expires_at =
          if expires_at, do: Enum.min([expires_at, max_expiry], DateTime), else: max_expiry

        CredentialLease.from_connection(
          conn,
          %{access_token: token, github_client: Jido.Connect.GitHub.Client},
          expires_at: expires_at,
          scopes: ["repo"]
        )

      {:error, reason} ->
        {:error, Error.auth("GitHub binding does not allow this read", reason: reason)}
    end
  end

  def resolve_lease(_, _, _),
    do:
      {:error, Error.auth("GitHub binding does not allow this operation", reason: :policy_denied)}

  def authorize(%{id: "github.issue.list"}, %{repo: repo}, context, connection) do
    case Store.lookup(context.tenant_id, slot(context.actor.id, context.tenant_id)) do
      {:ok, %{repo: ^repo, ref: ref, connection: %{id: connection_id}}}
      when ref == context.metadata.binding_ref and connection_id == connection.id ->
        :ok

      _ ->
        {:deny, :outside_agent_binding}
    end
  end

  def authorize(_, _, _, _), do: {:deny, :outside_agent_binding}

  defp slot(id, owner), do: String.replace_prefix(id, owner <> ":", "")

  defp lookup(owner, slot) do
    case Store.lookup(owner, slot) do
      {:ok, binding} -> {:ok, binding}
      :error -> {:error, :github_connection_required}
    end
  end

  defp start_agent(id) do
    case Jido.whereis_agent(ConnectBot.Jido, id) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        case Jido.start_agent(ConnectBot.Jido, IssueAgent, id: id) do
          {:error, {:already_started, pid}} -> {:ok, pid}
          result -> result
        end
    end
  end
end
