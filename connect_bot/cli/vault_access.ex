defmodule ConnectBot.VaultAccess do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  alias ConnectBot.VaultDelegation

  @operation "github.issue.list"

  @impl true
  def describe(_opts), do: "the authenticated principal can manage or lease this credential"

  @impl true
  def match?(
        %{type: :user, tenant_id: tenant, user_id: user},
        %{subject: %Ash.Changeset{tenant: tenant, action: %{name: :bind}} = changeset},
        _
      ) do
    Ash.Changeset.get_attribute(changeset, :owner_id) == user and
      VaultDelegation.permitted?(tenant, user, :manage)
  end

  def match?(
        %{type: :agent, tenant_id: tenant, user_id: user, agent_id: agent, grant_id: grant_id},
        %{
          subject: %Ash.Query{tenant: tenant, arguments: %{agent_id: agent, repo: repo, ref: ref}}
        },
        _
      ) do
    allowed_lease?(grant_id, tenant, user, agent, repo, ref)
  end

  def match?(
        %{type: :agent, tenant_id: tenant, user_id: user, agent_id: agent, grant_id: grant_id},
        %{
          subject: %Ash.Changeset{
            tenant: tenant,
            action: %{name: :rotate_tokens},
            data: %{id: agent, tenant_id: tenant, owner_id: user, repo: repo, ref: ref}
          }
        },
        _
      ) do
    allowed_lease?(grant_id, tenant, user, agent, repo, ref)
  end

  def match?(_, _, _), do: false

  def allowed_lease?(nil, tenant, user, _agent, _repo, _ref),
    do: VaultDelegation.permitted?(tenant, user, :use)

  def allowed_lease?(grant_id, tenant, user, agent, repo, ref) when is_binary(grant_id) do
    VaultDelegation.with_active_grant(grant_id, fn
      %{
        tenant: ^tenant,
        user: ^user,
        agent: ^agent,
        operation: @operation,
        repo: ^repo,
        binding_ref: ^ref
      } ->
        true

      _ ->
        false
    end) == true
  end

  def allowed_lease?(_, _, _, _, _, _), do: false
end
