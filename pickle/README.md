# Pickle

Pickle is a Phoenix 1.8 app that mounts Jidoka at `/jidoka`. It uses
the generated `PickleWeb.Endpoint` and the local Jidoka source dependency.
See the [Jidoka installation guide](../../jidoka/docs/operations/embedded.md)
for the package installation and migration contract.

For this local spike, Pickle uses PostgreSQL on port 55432. Create
`pickle_dev` and a separate `pickle_jidoka` database. Update
`config/dev.exs` if your Pickle database uses other connection settings.
Set `JIDOKA_DATABASE_URL`, `JIDOKA_DATA_ROOT`, and `JIDOKA_VAULT_KEY`
as shown in the installation guide. The smoke test can use a local
Ollama model.

From the Jidoka checkout, run `mix deps.get` and `mix assets.deploy`.
Then run these commands from Pickle.

```sh
mix deps.get
mix ecto.migrate
mix assets.setup
PORT=4015 mix phx.server
```

Open [Pickle](http://localhost:4015/) and
[Jidoka in Pickle](http://localhost:4015/jidoka).
