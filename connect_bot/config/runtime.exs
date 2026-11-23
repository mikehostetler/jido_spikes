import Config

config :connect_bot, :github_oauth,
  client_id: System.get_env("CONNECT_BOT_GITHUB_CLIENT_ID"),
  client_secret: System.get_env("CONNECT_BOT_GITHUB_CLIENT_SECRET"),
  redirect_uri:
    System.get_env("CONNECT_BOT_GITHUB_REDIRECT_URI") ||
      "http://localhost:4000/integrations/github/oauth/callback"

if System.get_env("CONNECT_BOT_LIVE_MODEL") == "1" do
  config :connect_bot, :inference_client, Jido.AI.InferenceClient.ReqLLM
end

if config_env() == :cli do
  state =
    System.get_env("CONNECT_BOT_STATE_DIR") ||
      Path.join(System.user_home!(), ".local/state/connect-bot")

  root = Path.join(state, "keys")
  config :connect_bot, vault_root: root, headless: true
  config :connect_bot, AshVault.KeyProviders.Local, root: root
  config :mnesia, dir: String.to_charlist(Path.join(state, "db"))
  config :logger, level: :warning
end
