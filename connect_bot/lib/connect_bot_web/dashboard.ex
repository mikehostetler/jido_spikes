defmodule ConnectBotWeb.Dashboard do
  use Phoenix.Controller, formats: [:html]

  alias ConnectBot.{GitHubOAuth, Host, Store}
  alias Jido.Connect.AccountSetup
  alias Jido.Connect.GitHub.AccountSetup, as: GitHubSetup

  plug(:ensure_owner)

  @slots ["first", "second"]

  def show(conn, _params), do: render_dashboard(conn)

  def connect(conn, %{"slot" => slot, "repo" => repo}) when slot in @slots and is_binary(repo) do
    case valid_repo?(repo) && GitHubOAuth.start(owner(conn), slot, repo) do
      {:ok, url} -> redirect(conn, external: url)
      false -> render_dashboard(conn, "Enter a repository as OWNER/REPO.")
      {:error, _} -> render_dashboard(conn, "Configure GitHub OAuth before connecting.")
    end
  end

  def connect(conn, _), do: send_resp(conn, 400, "Invalid agent or repository.")

  def import_key(conn, %{"slot" => slot, "repo" => repo, "token" => token})
      when slot in @slots and is_binary(repo) and is_binary(token) do
    with true <- valid_repo?(repo),
         {:ok, credential} <- AccountSetup.import_key(GitHubSetup, token),
         :ok <- Store.bind(owner(conn), slot, repo, credential) do
      redirect(conn, to: "/")
    else
      _ -> render_dashboard(conn, "Check the repository and GitHub token.")
    end
  end

  def import_key(conn, _), do: send_resp(conn, 400, "Invalid agent or repository.")

  def callback(conn, %{"code" => code, "state" => state}) do
    case GitHubOAuth.finish(owner(conn), code, state) do
      :ok ->
        redirect(conn, to: "/")

      {:error, _} ->
        render_dashboard(conn, "GitHub could not be connected. Start again from the dashboard.")
    end
  end

  def callback(conn, _), do: render_dashboard(conn, "GitHub sign-in was not completed.")

  def read(conn, %{"slot" => slot}) when slot in @slots do
    case Host.read(owner(conn), slot) do
      {:ok, issues} ->
        render_dashboard(conn, issues)

      {:error, :github_connection_required} ->
        render_dashboard(conn, "Connect GitHub first.")

      {:error, _} ->
        render_dashboard(
          conn,
          "The agent could not read issues. Check the repository and GitHub grant."
        )
    end
  end

  def read(conn, _), do: send_resp(conn, 404, "Unknown agent.")

  def disconnect(conn, %{"slot" => slot}) when slot in @slots do
    Store.revoke(owner(conn), slot)
    redirect(conn, to: "/")
  end

  def disconnect(conn, _), do: send_resp(conn, 404, "Unknown agent.")

  defp ensure_owner(conn, _opts) do
    if owner(conn), do: conn, else: put_session(conn, :owner, Store.nonce())
  end

  defp owner(conn), do: get_session(conn, :owner)

  defp valid_repo?(repo),
    do: Regex.match?(~r/\A[a-zA-Z0-9-]+\/(?!\.\.?\z)[a-zA-Z0-9_.-]+\z/, repo)

  defp render_dashboard(conn, result \\ nil) do
    token = get_csrf_token()
    cards = Enum.map_join(@slots, &card(owner(conn), &1, token))

    notice =
      if GitHubOAuth.configured?(),
        do: "",
        else: "<p>Configure GitHub OAuth to connect an account.</p>"

    result = if result, do: "<h2>Result</h2><pre>#{escape(result)}</pre>", else: ""

    html(conn, """
    <!doctype html>
    <html lang="en">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Connect Bot</title>
    <style>
      body { font: 1rem system-ui; margin: 3rem auto; padding: 0 1rem; max-width: 48rem; color: #172134; }
      section, pre { border: 1px solid #cad4e0; border-radius: .5rem; padding: 1rem; margin: 1rem 0; }
      form { margin: .5rem 0; }
      input, button { font: inherit; padding: .35rem .55rem; }
      pre { white-space: pre-wrap; }
    </style>
    <main>
      <h1>Connect Bot</h1>
      #{notice}
      #{cards}
      #{result}
    </main>
    </html>
    """)
  end

  defp card(owner, slot, token) do
    {repo, actions} =
      case Store.lookup(owner, slot) do
        {:ok, %{repo: repo}} ->
          {repo,
           form("/agents/#{slot}/read", token, "<button>Read open issues</button>") <>
             form("/agents/#{slot}/disconnect", token, "<button>Disconnect</button>")}

        :error ->
          {"", "<p>GitHub is disconnected.</p>"}
      end

    connect = """
    <label>Repository <input required name="repo" placeholder="OWNER/REPO" value="#{escape(repo)}"></label>
    <button>Connect GitHub</button>
    """

    import = """
    <label>Repository <input required name="repo" placeholder="OWNER/REPO" value="#{escape(repo)}"></label>
    <label>GitHub token <input required name="token" type="password" autocomplete="off"></label>
    <button>Import token</button>
    """

    """
    <section>
      <h2>#{String.capitalize(slot)} agent</h2>
      #{form("/agents/#{slot}/connect", token, connect)}
      #{form("/agents/#{slot}/import", token, import)}
      #{actions}
    </section>
    """
  end

  defp form(path, token, body) do
    """
    <form method="post" action="#{path}">
      <input type="hidden" name="_csrf_token" value="#{escape(token)}">
      #{body}
    </form>
    """
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
