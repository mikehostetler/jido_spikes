defmodule ConnectBot.VaultHost do
  @behaviour Jido.Connect.CredentialResolver

  alias ConnectBot.{Host, Vault, VaultAccess, VaultBinding, VaultDelegation}
  alias Jido.Connect.{AccountSetup, Context, CredentialLease, Error}
  alias Jido.Connect.AccountSetup.Credential
  alias Jido.Connect.GitHub.AccountSetup, as: GitHubSetup
  alias Jido.Connect.GitHub.{Client, Connections}

  require Ash.Query

  @local %{tenant_id: "connect-bot-local", user_id: "local-operator", type: :user}
  @operation "github.issue.list"

  def local_principal, do: @local

  def setup do
    root = Application.fetch_env!(:connect_bot, :vault_root)

    for dir <- [Path.dirname(root), root, Path.join(Path.dirname(root), "db")] do
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o700)
    end

    Vault.setup()
  end

  def start_storage do
    with {:ok, _pid} <- Supervisor.start_link(Vault.child_specs(), strategy: :one_for_one),
         :ok <- ensure_tables(),
         :ok <- :mnesia.wait_for_tables([VaultBinding, VaultDelegation.table()], 5_000),
         :ok <- upgrade_local_bindings(),
         :ok <- VaultDelegation.bootstrap(@local.tenant_id, @local.user_id) do
      :ok
    else
      _ -> {:error, :storage_unavailable}
    end
  end

  def bind(agent_id, repo, token), do: bind(@local, agent_id, repo, token)

  def bind(principal, agent_id, repo, token) when is_binary(token) do
    with {:ok, credential} <- AccountSetup.import_key(GitHubSetup, token) do
      bind(principal, agent_id, repo, credential)
    end
  end

  def bind(
        %{type: :user, tenant_id: tenant, user_id: user} = principal,
        agent_id,
        repo,
        %Credential{} = credential
      ) do
    attrs =
      Map.merge(token_attrs(credential), %{
        id: agent_id,
        owner_id: user,
        ref: Ash.UUID.generate(),
        repo: repo
      })

    result =
      VaultDelegation.transaction(fn ->
        if VaultDelegation.permitted?(tenant, user, :manage) do
          VaultBinding
          |> Ash.Changeset.for_create(:bind, attrs,
            actor: principal,
            tenant: tenant,
            authorize?: true
          )
          |> Ash.create()
        else
          {:error, :credential_management_denied}
        end
      end)

    case result do
      {:ok, _binding} -> :mnesia.sync_log()
      {:error, :credential_management_denied} = denied -> denied
      {:error, _error} -> {:error, :binding_write_failed}
    end
  end

  def read(agent_id, requested_repo \\ nil), do: read(@local, agent_id, requested_repo)

  def read(principal, agent_id, requested_repo) do
    with {:ok, binding} <- binding(principal, agent_id),
         {:ok, context} <- turn_context(binding) do
      run_turn(requested_repo || binding.repo, context)
    end
  end

  def binding(%{type: :user, tenant_id: tenant} = principal, agent_id) do
    VaultBinding
    |> Ash.Query.for_read(:binding, %{}, actor: principal, tenant: tenant, authorize?: true)
    |> Ash.Query.filter(id == ^agent_id)
    |> read_binding()
  end

  def set_membership(active?) when is_boolean(active?) do
    permissions = if active?, do: [:manage, :use, :delegate], else: []
    VaultDelegation.set_membership(@local.tenant_id, @local.user_id, permissions)
  end

  def delegate(agent_id), do: delegate(@local, agent_id)

  def delegate(principal, agent_id) do
    with {:ok, binding} <- binding(principal, agent_id) do
      VaultDelegation.issue(principal, @operation, binding)
    end
  end

  def revoke(grant_id), do: revoke(@local, grant_id)

  def revoke(%{type: :user, tenant_id: tenant, user_id: user}, grant_id),
    do: VaultDelegation.revoke(grant_id, tenant, user)

  def enqueue(grant_id), do: enqueue(@local, grant_id)

  def enqueue(%{type: :user, tenant_id: tenant, user_id: user}, grant_id),
    do: VaultDelegation.enqueue(grant_id, tenant, user)

  def execute(run_id), do: execute(@local, run_id)

  def execute(%{type: :user, tenant_id: tenant, user_id: user} = principal, run_id) do
    with {:ok, grant} <- VaultDelegation.claim(run_id, tenant, user) do
      result = execute_grant(principal, grant)
      status = if match?({:ok, _}, result), do: :succeeded, else: :failed
      with :ok <- VaultDelegation.finish(run_id, status), do: result
    end
  end

  defp execute_grant(principal, grant) do
    with {:ok, %{ref: ref, repo: repo} = binding} <- binding(principal, grant.agent),
         true <- ref == grant.binding_ref and repo == grant.repo,
         {:ok, context} <- turn_context(binding, grant.id) do
      run_turn(grant.repo, context)
    else
      _ -> {:error, :delegation_denied}
    end
  end

  defp run_turn(repo, %{integration_context: %{connection: %{id: id}}} = context),
    do: Host.run_turn(id, repo, context)

  def turn_context(binding, grant_id \\ nil) do
    with {:ok, connection} <-
           Connections.user_connection(
             id: connection_id(binding.tenant_id, binding.owner_id, binding.id),
             tenant_id: binding.tenant_id,
             owner_id: binding.owner_id,
             credential_ref: binding.ref,
             scopes: binding.scopes || ["repo"]
           ) do
      {:ok,
       %{
         integration_context:
           Context.new!(%{
             tenant_id: binding.tenant_id,
             actor: %{id: binding.id, type: :agent},
             connection: connection,
             metadata: %{grant_id: grant_id}
           }),
         credential_resolver: __MODULE__,
         policy: __MODULE__,
         jido_ai_inference_client: ConnectBot.ScriptedModel
       }}
    end
  end

  @impl true
  def resolve_lease(context, @operation, %{
        repo: repo,
        state: "open",
        page: 1,
        per_page: 30
      }) do
    result =
      case read_lease(context, repo) do
        {:refresh, actor} -> refresh_lease(context, repo, actor)
        other -> other
      end

    case result do
      {:ok, %CredentialLease{}} -> result
      {:error, %Error.AuthError{}} -> result
      _ -> deny_lease()
    end
  end

  def resolve_lease(_, _, _), do: deny_lease()

  defp deny_lease,
    do:
      {:error, Error.auth("Vault binding did not authorize this action", reason: :policy_denied)}

  defp read_lease(context, repo) do
    VaultDelegation.transaction(fn ->
      with {:ok, actor, args} <- access(context, repo),
           {:ok, binding} <- read_runtime(:for_lease, actor, args, []) do
        case lease_expiration(binding.expires_at) do
          {:ok, expires_at} ->
            with {:ok, %{token: token}} when is_binary(token) <-
                   read_runtime(:for_lease, actor, args, [:token]) do
              CredentialLease.from_connection(
                context.connection,
                %{access_token: token, github_client: Client},
                expires_at: expires_at,
                scopes: binding.scopes || ["repo"]
              )
            end

          :expired ->
            {:refresh, actor}
        end
      end
    end)
  end

  defp refresh_lease(context, repo, actor) do
    key = {__MODULE__, :refresh, actor.tenant_id, actor.user_id, actor.agent_id}

    :global.trans(
      {key, self()},
      fn ->
        case read_lease(context, repo) do
          {:refresh, _} ->
            with :ok <- refresh_token(context, repo) do
              case read_lease(context, repo) do
                {:refresh, _} -> reconnect_required()
                result -> result
              end
            end

          result ->
            result
        end
      end,
      [node()]
    )
  end

  defp refresh_token(context, repo) do
    opts = Application.fetch_env!(:connect_bot, :github_oauth)
    opts = Keyword.put(opts, :required_scopes, ["repo"])

    with {:ok, token} <- read_refresh_token(context, repo),
         {:ok, %Credential{fields: %{refresh_token: _}, expires_at: %DateTime{}} = credential} <-
           AccountSetup.refresh(GitHubSetup, token, opts) do
      rotate_tokens(context, repo, credential)
    else
      {:error, %Error.AuthError{}} = error -> error
      _ -> reconnect_required()
    end
  end

  defp read_refresh_token(context, repo) do
    VaultDelegation.transaction(fn ->
      with {:ok, actor, args} <- access(context, repo),
           {:ok, binding} <- read_runtime(:for_lease, actor, args, []),
           {:ok, _} <- lease_expiration(binding.refresh_expires_at),
           {:ok, %{refresh_token: token}} when is_binary(token) <-
             read_runtime(:for_refresh, actor, args, [:refresh_token]) do
        {:ok, token}
      else
        :expired -> reconnect_required()
        {:ok, %{refresh_token: _}} -> reconnect_required()
        error -> error
      end
    end)
  end

  defp rotate_tokens(context, repo, credential) do
    result =
      VaultDelegation.transaction(fn ->
        with {:ok, actor, args} <- access(context, repo),
             {:ok, binding} <- read_runtime(:for_lease, actor, args, []) do
          binding
          |> Ash.Changeset.for_update(:rotate_tokens, token_attrs(credential),
            actor: actor,
            tenant: actor.tenant_id,
            authorize?: true
          )
          |> Ash.update()
        end
      end)

    case result do
      {:ok, _} -> :mnesia.sync_log()
      _ -> deny_lease()
    end
  end

  defp token_attrs(credential) do
    %{
      token: credential.fields.access_token,
      refresh_token: Map.get(credential.fields, :refresh_token),
      expires_at: credential.expires_at,
      refresh_expires_at: credential.refresh_expires_at,
      scopes: credential.scopes
    }
  end

  defp reconnect_required,
    do: {:error, Error.auth("Reconnect GitHub", reason: :reconnect_required)}

  defp lease_expiration(provider_expiration) do
    now = DateTime.utc_now()
    lease_expiration = DateTime.add(now, 60, :second)

    cond do
      is_nil(provider_expiration) or DateTime.after?(provider_expiration, lease_expiration) ->
        {:ok, lease_expiration}

      DateTime.after?(provider_expiration, now) ->
        {:ok, provider_expiration}

      true ->
        :expired
    end
  end

  def authorize(%{id: @operation}, %{repo: repo}, context, _connection) do
    case access(context, repo) do
      {:ok, _actor, _args} -> :ok
      _ -> {:deny, :outside_agent_binding}
    end
  end

  def authorize(_, _, _, _), do: {:deny, :outside_agent_binding}

  defp access(
         %{
           tenant_id: tenant,
           actor: %{id: agent, type: :agent},
           connection: %{
             id: id,
             provider: :github,
             profile: :user,
             status: :connected,
             tenant_id: tenant,
             owner_type: :app_user,
             owner_id: user,
             credential_ref: ref
           },
           metadata: %{grant_id: grant_id}
         },
         repo
       ) do
    with true <- id == connection_id(tenant, user, agent),
         true <- VaultAccess.allowed_lease?(grant_id, tenant, user, agent, repo, ref) do
      actor = %{
        type: :agent,
        tenant_id: tenant,
        user_id: user,
        agent_id: agent,
        grant_id: grant_id
      }

      {:ok, actor, %{agent_id: agent, repo: repo, ref: ref}}
    else
      _ -> {:error, :outside_agent_binding}
    end
  end

  defp access(_, _), do: {:error, :outside_agent_binding}

  defp read_runtime(action, actor, args, load) do
    VaultBinding
    |> Ash.Query.for_read(action, args,
      actor: actor,
      tenant: actor.tenant_id,
      authorize?: true
    )
    |> Ash.Query.load(load)
    |> read_binding()
  end

  defp read_binding(query) do
    case Ash.read_one(query) do
      {:ok, %VaultBinding{}} = result -> result
      _ -> {:error, :binding_unavailable}
    end
  end

  defp connection_id(tenant, user, agent) do
    if tenant == @local.tenant_id and user == @local.user_id do
      agent
    else
      "agent:" <> Base.url_encode64(:erlang.term_to_binary({tenant, user, agent}), padding: false)
    end
  end

  defp ensure_tables do
    with :ok <- ensure_disk_schema(),
         :ok <- ensure_table(VaultBinding, [:_pkey, :val]) do
      ensure_table(VaultDelegation.table(), [:key, :value])
    end
  end

  defp ensure_table(table, attrs) do
    case :mnesia.create_table(table, attributes: attrs, disc_copies: [node()]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^table}} -> :ok
      _ -> {:error, :table_unavailable}
    end
  end

  defp ensure_disk_schema do
    case :mnesia.table_info(:schema, :storage_type) do
      :disc_copies ->
        :ok

      :ram_copies ->
        case :mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
          {:atomic, :ok} -> :ok
          _ -> {:error, :schema_unavailable}
        end
    end
  end

  defp upgrade_local_bindings do
    meta_table = VaultDelegation.table()
    marker = :tenant_binding_schema

    case :mnesia.sync_transaction(fn ->
           if :mnesia.read(meta_table, marker, :write) == [] do
             :mnesia.foldl(&upgrade_local_binding/2, :ok, VaultBinding)
             :mnesia.write({meta_table, marker, true})
           end

           :ok
         end) do
      {:atomic, :ok} -> :mnesia.sync_log()
      {:aborted, _} -> {:error, :storage_unavailable}
    end
  end

  defp upgrade_local_binding({VaultBinding, [_agent_id] = key, attrs}, :ok) do
    scoped = Map.merge(attrs, %{tenant_id: @local.tenant_id, owner_id: @local.user_id})
    new_key = Enum.map(Ash.Resource.Info.primary_key(VaultBinding), &Map.fetch!(scoped, &1))
    :ok = :mnesia.write({VaultBinding, new_key, scoped})
    :mnesia.delete({VaultBinding, key})
    :ok
  end

  defp upgrade_local_binding(_row, :ok), do: :ok
end
