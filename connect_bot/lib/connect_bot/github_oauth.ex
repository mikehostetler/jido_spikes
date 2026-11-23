defmodule ConnectBot.GitHubOAuth do
  alias ConnectBot.Store
  alias Jido.Connect.AccountSetup
  alias Jido.Connect.GitHub.AccountSetup, as: GitHubSetup

  def start(owner, slot, repo) do
    with {:ok, opts} <- options(),
         {:ok, url, flow} <-
           AccountSetup.start_browser(GitHubSetup, owner, %{slot: slot, repo: repo}, opts),
         :ok <- Store.save_oauth(flow) do
      {:ok, url}
    end
  end

  def finish(owner, code, state) do
    with {:ok, opts} <- options(),
         {:ok, target, credential} <-
           AccountSetup.finish_browser(
             GitHubSetup,
             owner,
             state,
             code,
             &Store.consume_oauth/2,
             opts
           ) do
      Store.bind(owner, target.slot, target.repo, credential, state)
    end
  end

  def configured?, do: match?({:ok, _}, options())

  def device_authorize(show_instructions) do
    opts = provider_options()

    with {:ok, flow} <- AccountSetup.start_device(GitHubSetup, opts) do
      show_instructions.(flow.verification_uri, flow.user_code)
      poll_device(flow, opts)
    end
  end

  defp poll_device(flow, opts) do
    case AccountSetup.poll_device(flow, opts) do
      {:pending, wait_ms, next_flow} ->
        Process.sleep(wait_ms)
        poll_device(next_flow, opts)

      result ->
        result
    end
  end

  defp options do
    opts = provider_options()

    if Enum.all?([:client_id, :client_secret, :redirect_uri], &(opts[&1] not in [nil, ""])) do
      {:ok, opts}
    else
      {:error, :configure_github_oauth}
    end
  end

  defp provider_options do
    :connect_bot
    |> Application.fetch_env!(:github_oauth)
    |> Keyword.merge(scope: ["repo"], required_scopes: ["repo"])
  end
end
