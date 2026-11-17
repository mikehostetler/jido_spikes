{:ok, _} = Application.ensure_all_started(:jido_work_system)

Ecto.Migrator.run(
  JidoWorkSystem.Repo,
  Path.expand("../db", __DIR__),
  :up,
  all: true
)

Ecto.Adapters.SQL.Sandbox.mode(JidoWorkSystem.Repo, :manual)
ExUnit.start()
