import Config

if config_env() == :cli do
  config :connect_bot, ash_domains: [ConnectBot.VaultDomain]
  config :ash, default_string_length_count: :codepoints
else
  config :phoenix, :filter_parameters, ["code", "state", "token", "secret"]

  config :connect_bot, ConnectBotWeb.Endpoint,
    adapter: Bandit.PhoenixAdapter,
    render_errors: [formats: [html: ConnectBotWeb.ErrorHTML], layout: false],
    http: [ip: {127, 0, 0, 1}, port: 4000],
    url: [host: "localhost", port: 4000],
    secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))
end

if config_env() == :test do
  config :logger, level: :warning
end
