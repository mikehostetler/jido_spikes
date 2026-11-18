[
  import_deps: [:ecto, :ecto_sql, :phoenix, :ash, :ash_sqlite, :ash_jido],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,scripts,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
