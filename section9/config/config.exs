import Config

config :phoenix, :json_library, Jason
config :req_llm, warn_unverified_models: false

config :section9,
  db_path: Path.expand("../data/section9.db", __DIR__),
  model_adapter: Section9.Model.Fake,
  model: System.get_env("SECTION9_MODEL", "lmstudio:lfm3-1.7b"),
  model_timeout: 120_000,
  pulse_limit: 12,
  mission_budget: 12,
  lease_ms: 60_000,
  dev_controls: false

config :section9, Section9Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: Section9Web.ErrorHTML], layout: false],
  pubsub_server: Section9.PubSub,
  live_view: [signing_salt: "section9-signing"],
  secret_key_base: String.duplicate("section9-local-demo-secret-", 4),
  server: false,
  http: [ip: {127, 0, 0, 1}, port: 4019]

import_config "#{config_env()}.exs"
