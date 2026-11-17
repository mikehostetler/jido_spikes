# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash, default_string_length_count: :codepoints

config :jido_work_system,
  generators: [timestamp_type: :utc_datetime_usec],
  ecto_repos: [JidoWorkSystem.Repo],
  ash_domains: [JidoWorkSystem.Work]

config :jido_work_system, JidoWorkSystem.Repo,
  database: Path.expand("../db/jido_work_system.db", __DIR__),
  priv: "repo",
  snapshots_path: Path.expand("../db/resource_snapshots", __DIR__),
  tenant_migrations_path: Path.expand("../db", __DIR__),
  pool_size: 5

# Configure the endpoint
config :jido_work_system, JidoWorkSystemWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: JidoWorkSystemWeb.ErrorHTML, json: JidoWorkSystemWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JidoWorkSystem.PubSub,
  live_view: [signing_salt: "lkhycBRP"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  jido_work_system: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  jido_work_system: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
