defmodule ConnectBot.VaultTest do
  use ExUnit.Case, async: false

  alias ConnectBot.{GitHubOAuth, Vault, VaultBinding, VaultDelegation, VaultHost}
  alias Jido.Connect.AccountSetup.Credential

  setup_all do
    refute Enum.any?(Application.started_applications(), &(elem(&1, 0) == :phoenix))
    :ok = VaultHost.setup()
    :ok = VaultHost.start_storage()
    :ok
  end

  test "headless OAuth stores a token pair and the generated action uses the access token" do
    api = fn conn ->
      case {conn.request_path, Plug.Conn.get_req_header(conn, "authorization")} do
        {"/user", ["Bearer device-access-token"]} ->
          send_json(conn, %{id: 21, login: "device-user"})

        {"/repos/example/device/issues", ["Bearer device-access-token"]} ->
          send_json(conn, [%{number: 30, title: "Device issue", state: "open"}])
      end
    end

    oauth = fn conn ->
      case conn.request_path do
        "/login/device/code" ->
          send_json(conn, %{
            device_code: "server-device-code",
            user_code: "DEVICE-CODE",
            verification_uri: "https://github.com/login/device",
            expires_in: 30,
            interval: 1
          })

        "/login/oauth/access_token" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          assert %{"device_code" => "server-device-code", "client_id" => "fixture-client"} =
                   URI.decode_query(body)

          send_json(conn, %{
            access_token: "device-access-token",
            refresh_token: "device-refresh-token",
            expires_in: 120,
            refresh_token_expires_in: 600,
            scope: "repo"
          })
      end
    end

    temporary_config(:connect_bot, :github_oauth, client_id: "fixture-client")
    temporary_config(:jido_connect_github, :github_oauth_req_options, plug: oauth)
    temporary_config(:jido_connect_github, :github_req_options, plug: api)

    assert {:ok, credential} =
             GitHubOAuth.device_authorize(fn uri, code ->
               assert uri == "https://github.com/login/device"
               assert code == "DEVICE-CODE"
             end)

    assert :ok = VaultHost.bind("device-reader", "example/device", credential)
    assert {:ok, binding} = VaultHost.binding(VaultHost.local_principal(), "device-reader")
    assert [{VaultBinding, _, row}] = table_record_for(binding)
    assert is_binary(row.encrypted_refresh_token)
    refute :erlang.term_to_binary(row) =~ "device-refresh-token"
    assert {:ok, "#30 Device issue"} = VaultHost.read("device-reader")
  end

  test "the generated Jido action reads with a vault lease and rejects other repositories" do
    token = "fixture-token-for-issues"
    :ok = VaultHost.bind("reader", "example/alpha", token)
    :ok = VaultHost.bind("another", "example/beta", "fixture-token-for-beta")

    assert {:ok, credential} = VaultHost.binding(VaultHost.local_principal(), "reader")

    assert credential.id == "reader"
    refute is_binary(credential.token)
    assert {:ok, context} = VaultHost.turn_context(credential)
    refute Map.has_key?(context, :credential_lease)
    assert :nomatch == :binary.match(:erlang.term_to_binary(context), token)

    assert [record] = table_record_for(credential)

    assert :nomatch == :binary.match(:erlang.term_to_binary(record), token)

    test_pid = self()

    use_issue_fixture(fn conn ->
      send(test_pid, {:github, conn.request_path})
      assert conn.request_path == "/repos/example/alpha/issues"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> token]
      "Vault fixture"
    end)

    params = %{repo: "example/alpha", state: "open", page: 1, per_page: 30}

    assert {:ok, _lease} =
             VaultHost.resolve_lease(context.integration_context, "github.issue.list", params)

    assert {:ok, "#7 Vault fixture"} = VaultHost.read("reader")
    assert_receive {:github, "/repos/example/alpha/issues"}
    assert {:error, :issue_read_failed} = VaultHost.read("reader", "example/beta")
    refute_received {:github, _}

    assert {:error, :delegation_denied} = VaultHost.delegate("reader")
    assert :ok = VaultHost.set_membership(true)
    assert {:ok, grant_id} = VaultHost.delegate("reader")
    assert {:ok, run_id} = VaultHost.enqueue(grant_id)
    assert {:ok, revoked_run_id} = VaultHost.enqueue(grant_id)

    assert {:ok, delegated_context} = VaultHost.turn_context(credential, grant_id)
    assert :nomatch == :binary.match(:erlang.term_to_binary(delegated_context), token)
    refute Map.has_key?(delegated_context, :credential_lease)

    table = VaultDelegation.table()
    assert :disc_copies == :mnesia.table_info(table, :storage_type)
    assert [{^table, {:run, ^run_id}, run}] = :mnesia.dirty_read(table, {:run, run_id})
    assert run.grant_id == grant_id
    assert :nomatch == :binary.match(:erlang.term_to_binary(run), token)

    assert {:ok, "#7 Vault fixture"} = VaultHost.execute(run_id)
    assert_receive {:github, "/repos/example/alpha/issues"}
    assert {:error, :run_unavailable} = VaultHost.execute(run_id)
    refute_received {:github, _}

    assert :ok = VaultHost.revoke(grant_id)
    assert {:error, :delegation_denied} = VaultHost.execute(revoked_run_id)

    assert {:error, %Jido.Connect.Error.AuthError{reason: :policy_denied}} =
             VaultHost.resolve_lease(
               delegated_context.integration_context,
               "github.issue.list",
               params
             )

    assert {:ok, second_grant_id} = VaultHost.delegate("reader")
    assert {:ok, member_run_id} = VaultHost.enqueue(second_grant_id)
    assert :ok = VaultHost.set_membership(false)
    assert :ok = VaultHost.set_membership(true)
    assert {:error, :delegation_denied} = VaultHost.execute(member_run_id)
    refute_received {:github, _}

    assert :ok = VaultHost.bind("reader", "example/alpha", "replacement-fixture")

    assert {:error, _} =
             VaultHost.resolve_lease(context.integration_context, "github.issue.list", %{
               repo: "example/alpha",
               state: "open",
               page: 1,
               per_page: 30
             })
  end

  test "concurrent leases exchange a rotating refresh token only once" do
    user = %{type: :user, tenant_id: "refresh-team", user_id: "owner"}
    repo = "example/refresh"
    authorize(user, [:manage, :delegate, :use])

    assert :ok = VaultHost.bind(user, "reader", repo, expired_credential())
    assert {:ok, binding} = VaultHost.binding(user, "reader")
    assert {:ok, grant} = VaultHost.delegate(user, "reader")
    assert {:ok, %{integration_context: context}} = VaultHost.turn_context(binding, grant)
    test_pid = self()

    use_refresh_fixture(fn conn ->
      send(test_pid, {:refresh_started, self()})

      receive do
        :finish_refresh -> refreshed_tokens(conn)
      after
        3_000 -> flunk("Test did not release the refresh request")
      end
    end)

    resolve = fn -> VaultHost.resolve_lease(context, "github.issue.list", issue_input(repo)) end
    first = Task.async(resolve)
    assert_receive {:refresh_started, worker}, 1_000
    second = Task.async(resolve)
    refute Task.yield(second, 100)
    refute_received {:refresh_started, _}
    send(worker, :finish_refresh)

    for task <- [first, second] do
      assert {:ok, lease} = Task.await(task)
      assert lease.fields.access_token == "rotated-access-token"
      refute Map.has_key?(lease.fields, :refresh_token)
    end

    refute_received {:refresh_started, _}
    assert {:ok, updated} = VaultHost.binding(user, "reader")
    assert updated.ref == binding.ref
    assert DateTime.after?(updated.expires_at, DateTime.utc_now())
    assert [{VaultBinding, _, %{encrypted_refresh_token: ciphertext}}] = table_record_for(updated)
    assert is_binary(ciphertext)
    refute ciphertext =~ "rotated-refresh-token"
  end

  test "tenant and owner policies enforce separate management, delegation, and lease permissions" do
    account_a = %{type: :user, tenant_id: "team-a", user_id: "sam"}
    account_b = %{type: :user, tenant_id: "team-b", user_id: "sam"}
    another_user = %{account_a | user_id: "lee"}

    authorize(account_a, [:manage])
    authorize(account_b, [:manage, :delegate, :use])
    authorize(another_user, [:manage, :delegate, :use])

    assert :ok = VaultHost.bind(account_a, "reader", "example/team-a", "token-a")
    assert :ok = VaultHost.bind(account_b, "reader", "example/team-b", "token-b")
    assert :ok = VaultHost.bind(another_user, "reader", "example/lee", "token-lee")

    assert {:ok, binding_a} = VaultHost.binding(account_a, "reader")
    assert {:ok, binding_b} = VaultHost.binding(account_b, "reader")
    assert {:ok, binding_lee} = VaultHost.binding(another_user, "reader")
    assert binding_a.repo == "example/team-a"
    assert binding_b.repo == "example/team-b"
    assert binding_lee.repo == "example/lee"

    assert {:ok, %{integration_context: context_a}} = VaultHost.turn_context(binding_a)
    assert {:ok, %{integration_context: context_b}} = VaultHost.turn_context(binding_b)
    assert {:ok, %{integration_context: context_lee}} = VaultHost.turn_context(binding_lee)
    assert context_a.connection.id != context_b.connection.id

    trace_decryption()

    assert {:error, :delegation_denied} = VaultHost.delegate(account_a, "reader")
    assert_denied(context_a, binding_a.repo)
    refute_received :decrypt_started

    authorize(account_a, [:delegate, :use])

    assert {:error, :credential_management_denied} =
             VaultHost.bind(account_a, "reader", binding_a.repo, "replacement")

    assert {:error, %Ash.Error.Forbidden{}} =
             VaultBinding
             |> Ash.Changeset.for_create(
               :bind,
               %{
                 id: binding_a.id,
                 owner_id: account_a.user_id,
                 ref: Ash.UUID.generate(),
                 repo: binding_a.repo,
                 token: "replacement"
               },
               actor: account_a,
               tenant: account_a.tenant_id
             )
             |> Ash.create()

    assert {:ok, grant_id} = VaultHost.delegate(account_a, "reader")
    assert {:ok, run_id} = VaultHost.enqueue(account_a, grant_id)
    assert {:ok, revoked_run_id} = VaultHost.enqueue(account_a, grant_id)
    assert {:error, :delegation_denied} = VaultHost.enqueue(account_b, grant_id)
    assert {:error, :delegation_denied} = VaultHost.revoke(another_user, grant_id)
    assert {:error, :run_unavailable} = VaultHost.execute(account_b, run_id)

    assert_denied(put_in(context_b.metadata.grant_id, grant_id), binding_b.repo)
    assert_denied(put_in(context_lee.metadata.grant_id, grant_id), binding_lee.repo)
    assert_denied(put_in(context_a.actor.id, "other-agent"), binding_a.repo)
    assert_denied(context_a, binding_b.repo)

    assert {:error, %Jido.Connect.Error.AuthError{reason: :policy_denied}} =
             VaultHost.resolve_lease(context_a, "github.issue.close", issue_input(binding_a.repo))

    assert [%{token: %Ash.ForbiddenField{}}] =
             VaultBinding
             |> Ash.Query.for_read(:binding, %{}, actor: account_a, tenant: account_a.tenant_id)
             |> Ash.Query.load(:token)
             |> Ash.read!()

    refute_received :decrypt_started

    {:ok, lease_a} =
      VaultHost.resolve_lease(context_a, "github.issue.list", issue_input(binding_a.repo))

    {:ok, lease_b} =
      VaultHost.resolve_lease(context_b, "github.issue.list", issue_input(binding_b.repo))

    assert lease_a.fields.access_token == "token-a"
    assert lease_b.fields.access_token == "token-b"
    assert_received :decrypt_started
    assert_received :decrypt_started

    assert [{VaultBinding, _, %{encrypted_token: ciphertext}}] = table_record_for(binding_a)

    assert_raise AshVault.Errors.CiphertextIntegrityFailed, fn ->
      Vault.decrypt!(ciphertext, %AshVault.Context{
        resource: VaultBinding,
        field: :token,
        ash_context: %{tenant: account_b.tenant_id}
      })
    end

    use_issue_fixture(fn conn ->
      case {conn.request_path, Plug.Conn.get_req_header(conn, "authorization")} do
        {"/repos/example/team-a/issues", ["Bearer token-a"]} -> "Team A issue"
        {"/repos/example/team-b/issues", ["Bearer token-b"]} -> "Team B issue"
        {path, _} -> flunk("Unexpected repository or credential for #{path}")
      end
    end)

    assert {:ok, "#7 Team A issue"} = VaultHost.execute(account_a, run_id)
    assert {:ok, "#7 Team B issue"} = VaultHost.read(account_b, "reader", nil)
    assert_received :decrypt_started
    assert_received :decrypt_started

    assert :ok = VaultHost.revoke(account_a, grant_id)
    assert {:error, :delegation_denied} = VaultHost.execute(account_a, revoked_run_id)
    assert_denied(put_in(context_a.metadata.grant_id, grant_id), binding_a.repo)
    refute_received :decrypt_started
  end

  test "reconnect replaces the credential while a refresh is in flight" do
    user = %{type: :user, tenant_id: "reconnect-team", user_id: "owner"}
    repo = "example/reconnect"
    authorize(user, [:manage, :use])
    assert :ok = VaultHost.bind(user, "reader", repo, expired_credential())
    assert {:ok, old} = VaultHost.binding(user, "reader")
    assert {:ok, %{integration_context: context}} = VaultHost.turn_context(old)
    test_pid = self()

    use_refresh_fixture(fn conn ->
      send(test_pid, {:refresh_started, self()})

      receive do
        :finish_refresh -> refreshed_tokens(conn)
      after
        3_000 -> flunk("Test did not release the refresh request")
      end
    end)

    task =
      Task.async(fn ->
        VaultHost.resolve_lease(context, "github.issue.list", issue_input(repo))
      end)

    assert_receive {:refresh_started, worker}, 1_000
    assert :ok = VaultHost.bind(user, "reader", repo, "replacement-token")
    send(worker, :finish_refresh)
    assert {:error, %Jido.Connect.Error.AuthError{reason: :policy_denied}} = Task.await(task)

    assert {:ok, replacement} = VaultHost.binding(user, "reader")
    assert replacement.ref != old.ref
    assert {:ok, %{integration_context: context}} = VaultHost.turn_context(replacement)
    assert {:ok, lease} = VaultHost.resolve_lease(context, "github.issue.list", issue_input(repo))
    assert lease.fields.access_token == "replacement-token"
  end

  defp authorize(principal, permissions) do
    assert :ok =
             VaultDelegation.set_membership(principal.tenant_id, principal.user_id, permissions)
  end

  defp assert_denied(context, repo) do
    assert {:error, %Jido.Connect.Error.AuthError{reason: :policy_denied}} =
             VaultHost.resolve_lease(context, "github.issue.list", issue_input(repo))
  end

  defp issue_input(repo), do: %{repo: repo, state: "open", page: 1, per_page: 30}

  defp trace_decryption do
    id = {__MODULE__, self()}

    :ok =
      :telemetry.attach(id, [:ash_vault, :decrypt, :start], &__MODULE__.on_decrypt/4, self())

    on_exit(fn -> :telemetry.detach(id) end)
  end

  def on_decrypt(_, _, %{resource: VaultBinding}, recipient),
    do: send(recipient, :decrypt_started)

  def on_decrypt(_, _, _, _), do: :ok

  defp table_record_for(binding) do
    key = Enum.map(Ash.Resource.Info.primary_key(VaultBinding), &Map.fetch!(binding, &1))
    :mnesia.dirty_read(VaultBinding, key)
  end

  defp use_issue_fixture(title_for_request) do
    api = fn conn ->
      title = title_for_request.(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        JSON.encode!([
          %{
            number: 7,
            title: title,
            state: "open",
            html_url: "https://github.com/example/team/issues/7"
          }
        ])
      )
    end

    previous = Application.fetch_env(:jido_connect_github, :github_req_options)
    Application.put_env(:jido_connect_github, :github_req_options, plug: api)

    on_exit(fn ->
      case previous do
        {:ok, options} -> Application.put_env(:jido_connect_github, :github_req_options, options)
        :error -> Application.delete_env(:jido_connect_github, :github_req_options)
      end
    end)
  end

  defp send_json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, JSON.encode!(body))
  end

  defp temporary_config(app, key, value) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(app, key, value)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  defp expired_credential do
    now = DateTime.utc_now()

    %Credential{
      fields: %{access_token: "expired-token", refresh_token: "one-use-refresh-token"},
      scopes: ["repo"],
      expires_at: DateTime.add(now, -60, :second),
      refresh_expires_at: DateTime.add(now, 600, :second)
    }
  end

  defp use_refresh_fixture(handle) do
    temporary_config(:connect_bot, :github_oauth,
      client_id: "fixture-client",
      client_secret: "fixture-client-secret"
    )

    oauth = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{"grant_type" => "refresh_token", "refresh_token" => "one-use-refresh-token"} =
               URI.decode_query(body)

      handle.(conn)
    end

    temporary_config(:jido_connect_github, :github_oauth_req_options, plug: oauth)
  end

  defp refreshed_tokens(conn) do
    send_json(conn, %{
      access_token: "rotated-access-token",
      refresh_token: "rotated-refresh-token",
      expires_in: 60,
      refresh_token_expires_in: 600,
      scope: "repo"
    })
  end
end
