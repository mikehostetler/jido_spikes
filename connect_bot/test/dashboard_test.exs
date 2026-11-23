defmodule ConnectBotWeb.DashboardTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest

  alias ConnectBot.{Host, Store}

  @endpoint ConnectBotWeb.Endpoint

  setup do
    owner = Store.nonce()
    test_pid = self()

    oauth_plug = fn conn ->
      assert conn.request_path == "/login/oauth/access_token"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"code" => code, "code_verifier" => verifier} = JSON.decode!(body)
      send(test_pid, {:exchange, code})
      send(test_pid, {:verifier, code, verifier})

      if code == "paused" do
        send(test_pid, {:pending_exchange, self()})

        receive do
          :complete_exchange -> :ok
        after
          3_000 -> flunk("Test did not release the OAuth exchange")
        end
      end

      fixture_json(conn, %{access_token: "fixture-token-#{code}", scope: "repo"})
    end

    api_plug = fn conn ->
      [authorization] = Plug.Conn.get_req_header(conn, "authorization")

      case {conn.request_path, authorization} do
        {"/user", "Bearer fixture-token-alpha"} ->
          fixture_json(conn, %{login: "alpha-owner", id: 11})

        {"/user", "Bearer fixture-token-beta"} ->
          fixture_json(conn, %{login: "beta-owner", id: 22})

        {"/user", "Bearer fixture-token-paused"} ->
          fixture_json(conn, %{login: "paused-owner", id: 33})

        {"/repos/example/alpha/issues", "Bearer fixture-token-alpha"} ->
          send(test_pid, {:issue_request, :alpha})
          fixture_json(conn, [%{number: 11, title: "Alpha issue", state: "open"}])

        {"/repos/example/beta/issues", "Bearer fixture-token-beta"} ->
          send(test_pid, {:issue_request, :beta})
          fixture_json(conn, [%{number: 22, title: "Beta issue", state: "open"}])

        _ ->
          send(test_pid, :unexpected_api_request)
          Plug.Conn.send_resp(conn, 403, "")
      end
    end

    config = [
      {:connect_bot, :github_oauth,
       [
         client_id: "fixture",
         client_secret: "fixture-secret",
         redirect_uri: "http://localhost:4000/integrations/github/oauth/callback"
       ]},
      {:jido_connect_github, :github_oauth_req_options, [plug: oauth_plug]},
      {:jido_connect_github, :github_req_options, [plug: api_plug]},
      {:connect_bot, :inference_client, ConnectBot.ScriptedModel}
    ]

    previous =
      Enum.map(config, fn {app, key, _} -> {app, key, Application.fetch_env(app, key)} end)

    Enum.each(config, fn {app, key, value} -> Application.put_env(app, key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {app, key, {:ok, value}} -> Application.put_env(app, key, value)
        {app, key, :error} -> Application.delete_env(app, key)
      end)
    end)

    %{owner: owner}
  end

  test "two Phoenix-connected instances read only their own repositories", %{owner: owner} do
    connect(owner, "first", "example/alpha", "alpha")
    connect(owner, "second", "example/beta", "beta")

    assert html_response(post(browser(owner), "/agents/first/read"), 200) =~ "#11 Alpha issue"
    assert_receive {:issue_request, :alpha}

    assert html_response(post(browser(owner), "/agents/second/read"), 200) =~ "#22 Beta issue"
    assert_receive {:issue_request, :beta}

    assert is_pid(Jido.whereis_agent(ConnectBot.Jido, Host.agent_id(owner, "first")))
    assert is_pid(Jido.whereis_agent(ConnectBot.Jido, Host.agent_id(owner, "second")))
    assert Host.agent_id(owner, "first") != Host.agent_id(owner, "second")

    assert {:error, :issue_read_failed} = Host.read(owner, "first", "example/beta")
    assert {:error, :issue_read_failed} = Host.read(owner, "second", "example/alpha")
    refute_received {:issue_request, _}
    refute_received :unexpected_api_request

    for slot <- ["first", "second"] do
      assert {:ok, binding} = Store.lookup(owner, slot)
      context = Host.turn_context(binding)
      assert context.integration_context.metadata == %{binding_ref: binding.ref}
      refute Map.has_key?(context, :credential_lease)
      assert :nomatch == :binary.match(:erlang.term_to_binary(context), "fixture-token-")
    end

    assert {:ok, binding} = Store.lookup(owner, "first")
    stale_context = Host.turn_context(binding)

    assert redirected_to(post(browser(owner), "/agents/first/disconnect")) == "/"
    assert {:error, :github_connection_required} = Host.read(owner, "first")

    assert {:error, %{reason: :github_connection_required}} =
             Host.resolve_lease(stale_context.integration_context, "github.issue.list", %{
               repo: "example/alpha",
               state: "open",
               page: 1,
               per_page: 30
             })

    assert {:ok, "#22 Beta issue"} = Host.read(owner, "second")
    assert_receive {:issue_request, :beta}
    refute_received :unexpected_api_request
  end

  test "OAuth callback requires the originating session and consumes state once", %{owner: owner} do
    query = start_oauth(owner, "first", "example/alpha")
    state = query["state"]

    assert html_response(callback("other-browser", "alpha", state), 200) =~
             "could not be connected"

    refute_received {:exchange, _}

    assert redirected_to(callback(owner, "alpha", state)) == "/"
    assert_receive {:exchange, "alpha"}
    assert_receive {:verifier, "alpha", verifier}

    assert query["code_challenge"] ==
             :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    assert html_response(callback(owner, "alpha", state), 200) =~ "could not be connected"
    refute_received {:exchange, _}
  end

  test "token import works and fences an older callback during reconnect", %{owner: owner} do
    connect(owner, "first", "example/alpha", "alpha")
    assert {:ok, prior_binding} = Store.lookup(owner, "first")
    state = start_oauth(owner, "first", "example/alpha")["state"]
    prior_callback = Task.async(fn -> callback(owner, "paused", state) end)
    assert_receive {:pending_exchange, worker}, 1_000

    conn =
      post(browser(owner), "/agents/first/import", %{
        "repo" => "example/beta",
        "token" => "fixture-token-beta"
      })

    assert redirected_to(conn) == "/"
    send(worker, :complete_exchange)
    assert html_response(Task.await(prior_callback), 200) =~ "could not be connected"

    assert {:ok, replacement} = Store.lookup(owner, "first")
    assert replacement.ref != prior_binding.ref
    assert {:ok, "#22 Beta issue"} = Host.read(owner, "first")
    assert_receive {:issue_request, :beta}
    assert {:error, :issue_read_failed} = Host.read(owner, "first", "example/alpha")
    refute_received {:issue_request, :alpha}
  end

  defp browser(owner) do
    build_conn()
    |> Plug.Test.init_test_session(%{owner: owner})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp connect(owner, slot, repo, code) do
    assert redirected_to(callback(owner, code, start_oauth(owner, slot, repo)["state"])) == "/"
    assert_receive {:exchange, ^code}
  end

  defp start_oauth(owner, slot, repo) do
    uri =
      browser(owner)
      |> post("/agents/#{slot}/connect", %{"repo" => repo})
      |> redirected_to()
      |> URI.parse()

    assert uri.host == "github.com"
    query = URI.decode_query(uri.query)
    assert query["redirect_uri"] == "http://localhost:4000/integrations/github/oauth/callback"
    assert query["code_challenge_method"] == "S256"
    query
  end

  defp callback(owner, code, state) do
    get(browser(owner), "/integrations/github/oauth/callback", %{"code" => code, "state" => state})
  end

  defp fixture_json(conn, value) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, JSON.encode!(value))
  end
end
