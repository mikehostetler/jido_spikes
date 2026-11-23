defmodule ConnectBot.Store do
  @moduledoc "In-memory account storage for the browser profile."
  use Agent

  alias Jido.Connect.AccountSetup.{BrowserFlow, Credential}
  alias Jido.Connect.GitHub.Connections

  def start_link(_opts) do
    Agent.start_link(fn -> %{bindings: %{}, secrets: %{}, oauth: %{}} end, name: __MODULE__)
  end

  def nonce, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def save_oauth(%BrowserFlow{} = flow) do
    now = DateTime.utc_now()
    key = {flow.principal, flow.target.slot}

    Agent.update(__MODULE__, fn store ->
      oauth =
        Map.reject(store.oauth, fn {_, %{flow: pending}} ->
          DateTime.before?(pending.expires_at, now)
        end)

      %{store | oauth: Map.put(oauth, key, %{flow: flow, consumed?: false})}
    end)
  end

  def consume_oauth(owner, state) do
    Agent.get_and_update(__MODULE__, fn store ->
      match =
        Enum.find(store.oauth, fn
          {{^owner, _}, %{flow: %{state: ^state}, consumed?: false}} -> true
          _ -> false
        end)

      case match do
        {key, %{flow: flow} = pending} ->
          {{:ok, flow}, put_in(store.oauth[key], %{pending | consumed?: true})}

        nil ->
          {{:error, :invalid_oauth_state}, store}
      end
    end)
  end

  def bind(owner, slot, repo, %Credential{} = credential, state \\ nil) do
    with {:ok, connection} <-
           Connections.user_connection(credential.subject,
             id: nonce(),
             tenant_id: owner,
             owner_id: owner,
             credential_ref: nonce(),
             scopes: credential.scopes
           ) do
      key = {owner, slot}
      binding = %{ref: nonce(), owner: owner, slot: slot, repo: repo, connection: connection}

      Agent.get_and_update(__MODULE__, fn store ->
        case {state, Map.get(store.oauth, key)} do
          {nil, _} ->
            {:ok, put_binding(store, key, binding, credential)}

          {state, %{consumed?: true, flow: %{state: state}}} ->
            {:ok, put_binding(store, key, binding, credential)}

          _ ->
            {{:error, :invalid_oauth_state}, store}
        end
      end)
    end
  end

  def lookup(owner, slot), do: Agent.get(__MODULE__, &Map.fetch(&1.bindings, {owner, slot}))

  def authorized_token(owner, agent_id, ref, connection_id, repo) do
    Agent.get(__MODULE__, fn store ->
      with {:ok, binding} <- find_binding(store, owner, agent_id, ref),
           true <- binding.connection.id == connection_id and binding.repo == repo,
           {:ok, credential} <- Map.fetch(store.secrets, binding.connection.credential_ref) do
        if is_nil(credential.expires_at) or
             DateTime.after?(credential.expires_at, DateTime.utc_now()) do
          {:ok, credential.fields.access_token, credential.expires_at}
        else
          {:error, :reconnect_required}
        end
      else
        false -> {:error, :repository_not_bound}
        :error -> {:error, :github_connection_required}
      end
    end)
  end

  def revoke(owner, slot) do
    key = {owner, slot}

    Agent.update(__MODULE__, fn store ->
      store = remove_binding(store, key)
      %{store | oauth: Map.delete(store.oauth, key)}
    end)
  end

  defp put_binding(store, key, binding, credential) do
    store = remove_binding(store, key)

    %{
      store
      | bindings: Map.put(store.bindings, key, binding),
        secrets: Map.put(store.secrets, binding.connection.credential_ref, credential),
        oauth: Map.delete(store.oauth, key)
    }
  end

  defp find_binding(store, owner, agent_id, ref) do
    Enum.find_value(["first", "second"], :error, fn slot ->
      case Map.fetch(store.bindings, {owner, slot}) do
        {:ok, %{ref: ^ref} = binding} ->
          if ConnectBot.Host.agent_id(owner, slot) == agent_id, do: {:ok, binding}

        _ ->
          nil
      end
    end)
  end

  defp remove_binding(store, key) do
    case Map.pop(store.bindings, key) do
      {nil, _} ->
        store

      {binding, bindings} ->
        %{
          store
          | bindings: bindings,
            secrets: Map.delete(store.secrets, binding.connection.credential_ref)
        }
    end
  end
end
