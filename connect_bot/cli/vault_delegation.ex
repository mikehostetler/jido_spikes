defmodule ConnectBot.VaultDelegation do
  @moduledoc false

  @table __MODULE__

  def table, do: @table

  def set_membership(tenant, user, permissions) when is_list(permissions) do
    key = {:member, tenant, user}

    persist(fn ->
      case {permissions, membership(read(key, :write))} do
        {[], _} ->
          write(key, nil)

        {_, %{id: id, permissions: previous}} ->
          preserves_grants? =
            [:delegate, :use] -- previous == [] and
              [:delegate, :use] -- permissions == []

          id = if preserves_grants?, do: id, else: Ash.UUID.generate()
          write(key, %{id: id, permissions: permissions})

        {_, nil} ->
          write(key, %{id: Ash.UUID.generate(), permissions: permissions})
      end
    end)
  end

  def bootstrap(tenant, user) do
    key = {:member, tenant, user}

    persist(fn ->
      if :mnesia.read(@table, key, :write) == [] do
        write(key, %{id: Ash.UUID.generate(), permissions: [:manage, :use]})
      else
        :ok
      end
    end)
  end

  def permitted?(tenant, user, permission) do
    transaction(fn ->
      case membership(read({:member, tenant, user})) do
        %{permissions: permissions} -> permission in permissions
        nil -> false
      end
    end) == true
  end

  def issue(
        %{tenant_id: tenant, user_id: user},
        operation,
        %{tenant_id: tenant, owner_id: user} = binding
      ) do
    grant = %{
      id: Ash.UUID.generate(),
      tenant: tenant,
      user: user,
      agent: binding.id,
      operation: operation,
      repo: binding.repo,
      binding_ref: binding.ref,
      revoked?: false
    }

    persist(fn ->
      with %{id: id, permissions: permissions} <- membership(read({:member, tenant, user})),
           true <- [:delegate, :use] -- permissions == [] do
        :ok = write({:grant, grant.id}, Map.put(grant, :membership, id))
        {:ok, grant.id}
      else
        _ -> {:error, :delegation_denied}
      end
    end)
  end

  def revoke(id, tenant, user) do
    persist(fn ->
      case read({:grant, id}, :write) do
        %{tenant: ^tenant, user: ^user} = grant ->
          write({:grant, id}, %{grant | revoked?: true})

        _ ->
          {:error, :delegation_denied}
      end
    end)
  end

  def enqueue(grant_id, tenant, user) do
    run_id = Ash.UUID.generate()

    persist(fn ->
      case active_grant(grant_id) do
        {:ok, %{tenant: ^tenant, user: ^user} = grant} ->
          run = %{grant_id: grant.id, tenant: tenant, user: user, status: :queued}
          :ok = write({:run, run_id}, run)
          {:ok, run_id}

        _ ->
          {:error, :delegation_denied}
      end
    end)
  end

  def claim(run_id, tenant, user) do
    persist(fn ->
      case read({:run, run_id}, :write) do
        %{status: :queued, grant_id: grant_id, tenant: ^tenant, user: ^user} = run ->
          case active_grant(grant_id) do
            {:ok, %{tenant: ^tenant, user: ^user} = grant} ->
              :ok = write({:run, run_id}, %{run | status: :running})
              {:ok, grant}

            {:error, :delegation_denied} ->
              :ok = write({:run, run_id}, %{run | status: :denied})
              {:error, :delegation_denied}

            {:ok, _other_grant} ->
              {:error, :delegation_denied}
          end

        _ ->
          {:error, :run_unavailable}
      end
    end)
  end

  def finish(run_id, status) when status in [:succeeded, :failed] do
    persist(fn ->
      case read({:run, run_id}, :write) do
        %{status: :running} = run -> write({:run, run_id}, %{run | status: status})
        _ -> {:error, :run_unavailable}
      end
    end)
  end

  def with_active_grant(id, fun) do
    transaction(fn ->
      with {:ok, grant} <- active_grant(id), do: fun.(grant)
    end)
  end

  defp active_grant(id) do
    with %{revoked?: false, tenant: tenant, user: user, membership: membership} = grant <-
           read({:grant, id}),
         %{id: ^membership, permissions: permissions} <- membership(read({:member, tenant, user})),
         true <- [:delegate, :use] -- permissions == [] do
      {:ok, grant}
    else
      _ -> {:error, :delegation_denied}
    end
  end

  defp membership(id) when is_binary(id),
    do: %{id: id, permissions: [:manage, :delegate, :use]}

  defp membership(%{} = member), do: member
  defp membership(nil), do: nil

  defp read(key, lock \\ :read) do
    case :mnesia.read(@table, key, lock) do
      [{@table, ^key, value}] -> value
      [] -> nil
    end
  end

  defp write(key, value), do: :mnesia.write({@table, key, value})

  defp persist(fun) do
    case :mnesia.sync_transaction(fun) do
      {:atomic, result} ->
        with :ok <- :mnesia.sync_log(), do: result

      {:aborted, _} ->
        {:error, :storage_unavailable}
    end
  end

  def transaction(fun) do
    case :mnesia.transaction(fun) do
      {:atomic, result} -> result
      {:aborted, _} -> {:error, :storage_unavailable}
    end
  end
end
