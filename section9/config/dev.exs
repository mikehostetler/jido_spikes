import Config

config :section9, Section9Web.Endpoint,
  server: true,
  code_reloader: false,
  debug_errors: true,
  check_origin: false

config :section9, dev_controls: true

config :logger, level: :info
