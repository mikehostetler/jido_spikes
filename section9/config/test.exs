import Config

config :section9,
  db_path: ":memory:",
  model_adapter: Section9.Model.Fake,
  lease_ms: 100,
  dev_controls: true

config :section9, Section9Web.Endpoint,
  server: false,
  secret_key_base: String.duplicate("section9-test-secret-", 5)

config :logger, level: :warning
