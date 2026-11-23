defmodule ConnectBot.VaultScope do
  @behaviour AshVault.Scope

  @impl true
  def resolve!(context) do
    case AshVault.Scopes.AshTenant.resolve!(context) do
      "connect-bot-local" -> "global"
      tenant -> "tenant:" <> tenant
    end
  end
end

defmodule ConnectBot.Vault do
  use AshVault.Vault,
    otp_app: :connect_bot,
    key_provider: AshVault.KeyProviders.Local,
    scope: ConnectBot.VaultScope
end

defmodule ConnectBot.VaultDomain do
  use Ash.Domain, otp_app: :connect_bot

  resources do
    resource(ConnectBot.VaultBinding)
  end
end

defmodule ConnectBot.VaultBinding do
  use Ash.Resource,
    otp_app: :connect_bot,
    domain: ConnectBot.VaultDomain,
    data_layer: Ash.DataLayer.Mnesia,
    extensions: [AshVault],
    authorizers: [Ash.Policy.Authorizer]

  alias ConnectBot.VaultAccess

  multitenancy do
    strategy(:attribute)
    attribute(:tenant_id)
  end

  ash_vault do
    vault(ConnectBot.Vault)
    scope(ConnectBot.VaultScope)
    encrypt(:token)
    encrypt(:refresh_token)
  end

  actions do
    read :binding do
      primary?(true)
    end

    read :for_lease do
      argument(:agent_id, :string, allow_nil?: false)
      argument(:repo, :string, allow_nil?: false)
      argument(:ref, :uuid, allow_nil?: false)
      filter(expr(id == ^arg(:agent_id) and repo == ^arg(:repo) and ref == ^arg(:ref)))
    end

    read :for_refresh do
      argument(:agent_id, :string, allow_nil?: false)
      argument(:repo, :string, allow_nil?: false)
      argument(:ref, :uuid, allow_nil?: false)
      filter(expr(id == ^arg(:agent_id) and repo == ^arg(:repo) and ref == ^arg(:ref)))
    end

    create :bind do
      accept([
        :id,
        :owner_id,
        :ref,
        :repo,
        :token,
        :refresh_token,
        :expires_at,
        :refresh_expires_at,
        :scopes
      ])

      upsert?(true)

      upsert_fields([
        :ref,
        :repo,
        :encrypted_token,
        :encrypted_refresh_token,
        :expires_at,
        :refresh_expires_at,
        :scopes
      ])
    end

    update :rotate_tokens do
      accept([:token, :refresh_token, :expires_at, :refresh_expires_at, :scopes])
      require_atomic?(false)
    end
  end

  policies do
    policy action([:bind, :rotate_tokens]) do
      authorize_if(VaultAccess)
    end

    policy action(:binding) do
      forbid_unless(actor_attribute_equals(:type, :user))
      authorize_if(expr(tenant_id == ^actor(:tenant_id) and owner_id == ^actor(:user_id)))
    end

    policy action([:for_lease, :for_refresh]) do
      forbid_unless(VaultAccess)
      authorize_if(expr(tenant_id == ^actor(:tenant_id) and owner_id == ^actor(:user_id)))
    end
  end

  field_policies do
    private_fields(:include)

    field_policy :token do
      authorize_if(action(:for_lease))
    end

    field_policy :refresh_token do
      authorize_if(action(:for_refresh))
    end

    field_policy [:encrypted_token, :encrypted_refresh_token] do
      forbid_if(always())
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    attribute(:id, :string, primary_key?: true, allow_nil?: false)
    attribute(:tenant_id, :string, primary_key?: true, allow_nil?: false)
    attribute(:owner_id, :string, primary_key?: true, allow_nil?: false)
    attribute(:ref, :uuid, allow_nil?: false)
    attribute(:repo, :string, allow_nil?: false)
    attribute(:token, :string, allow_nil?: false, sensitive?: true)
    attribute(:refresh_token, :string, sensitive?: true)
    attribute(:expires_at, :utc_datetime_usec)
    attribute(:refresh_expires_at, :utc_datetime_usec)
    attribute(:scopes, {:array, :string}, default: ["repo"])
  end
end
