# Connect Bot

A local Phoenix app runs the same Jido AI agent in two instances. Each instance
has its own GitHub connection and repository binding. The
[agent DSL](lib/connect_bot/issue_agent.ex) registers
`Jido.Connect.GitHub.Actions.ListIssues` directly.

## Read issues from AshVault without Phoenix

The CLI profile uses the same `ConnectBot.IssueAgent` and generated
`Jido.Connect.GitHub.Actions.ListIssues` action as the dashboard. Install the
CLI dependencies and initialize its local store:

```sh
MIX_ENV=cli mix deps.get
./connect-bot vault init
gh auth token --hostname github.com | ./connect-bot vault bind issues elixir-lang/elixir
./connect-bot vault read issues
```

To use OAuth in the CLI, enable device flow in the GitHub OAuth app, set
`CONNECT_BOT_GITHUB_CLIENT_ID`, and run `./connect-bot vault connect issues
elixir-lang/elixir`. The CLI displays the verification URL and user code.
For expiring OAuth credentials, set `CONNECT_BOT_GITHUB_CLIENT_SECRET` in the
host environment. The vault stores the access and refresh tokens together and
serializes refresh by binding. Reconnect replaces the binding reference.

Use a GitHub token that can read the bound repository and satisfies the
connector's GitHub user profile. The bind command reads it from standard
input. The read command obtains the token from AshVault and works across
separate CLI processes. It uses scripted inference and makes the issue
request through the generated action.

The default state directory is `~/.local/state/connect-bot`. Set
`CONNECT_BOT_STATE_DIR` to select another directory. Mnesia stores ciphertext
in `db/` and AshVault stores local keys in `keys/`. This is a single-operator,
single-node CLI. The local operating system account controls the state
directory. Host calls to `VaultHost` accept an authenticated tenant and user.
Ash policies enforce tenant and owner boundaries, and AshVault uses a separate
key scope for each tenant. The host reloads `:manage`, `:delegate`, and `:use`
permissions from storage. A run must match its current agent, operation,
repository, and binding reference before AshVault decrypts the token.
Rebinding replaces the token and invalidates old binding references. The
local CLI opens existing bindings and grants from the earlier store format.

For a background run, the local operator enables their membership and creates
an explicit grant for the agent's current repository binding. Run each command
as a separate CLI process:

```sh
./connect-bot vault member enable
grant_id=$(./connect-bot vault delegate issues)
run_id=$(./connect-bot vault enqueue "$grant_id")
./connect-bot vault execute "$run_id"

revoked_run_id=$(./connect-bot vault enqueue "$grant_id")
./connect-bot vault revoke "$grant_id"
./connect-bot vault execute "$revoked_run_id"  # fails before the GitHub request
```

The queued record holds the grant ID and local owner IDs. The worker loads the
current grant and membership. The resolver checks them again before it reads
the credential. Disabling membership invalidates its grants. Re-enabling
membership requires new grants. The CLI runs one queued job on demand and
claims it once. A worker that exits after it claims a run leaves that run in
the `running` state.

The CLI tests give two tenants the same user and agent names. They also add a
second owner in one tenant. The tests check which token reaches the GitHub
client and check that denied requests do not start AshVault decryption.

```sh
ERL_CRASH_DUMP_SECONDS=0 CONNECT_BOT_STATE_DIR="$(mktemp -d)" MIX_ENV=cli mix test
```

## Run the dashboard

Use the sibling Jido Connect checkout with the v3 credential resolver change
and Jido `3.0.0-beta.3`. Install its dependencies first.

Create a GitHub OAuth App with this authorization callback URL:

```text
http://localhost:4000/integrations/github/oauth/callback
```

Set `CONNECT_BOT_GITHUB_CLIENT_ID` and `CONNECT_BOT_GITHUB_CLIENT_SECRET` in
your shell. From this directory run:

```sh
mix phx.server
```

Open [the local dashboard](http://localhost:4000). Enter a repository for each
agent and click **Connect GitHub**. When GitHub returns to the dashboard,
click **Read open issues**. Click **Disconnect** to remove that instance's
local grant and token. The other agent keeps its connection.

Use **Import token** to connect without browser OAuth. The CLI and dashboard
use `Jido.Connect.AccountSetup` with `Jido.Connect.GitHub.AccountSetup` for
token import and OAuth. The browser callback must use the originating session,
client ID, and redirect URI. A new setup attempt, token import, or disconnect
prevents an earlier callback from changing the binding.

The app runs on loopback and uses a private browser session as its demo
principal. Bindings and tokens live in host memory and reset when the app
restarts. A production app would use its signed-in user and tenant, persist
bindings, and put tokens in its credential store.

Scripted inference is the default. Set `CONNECT_BOT_LIVE_MODEL=1` and
`OPENAI_API_KEY` to use OpenAI. This sends the issue results to the model
provider. GitHub's OAuth user profile uses a broad `repo` grant. The host
limits each agent to reading the first page of open issues in its bound
repository. For a production read-only install, evaluate GitHub App
installation tokens with repository-specific Issues read access.

## Verify without credentials

```sh
mix test
```

The tests drive the Phoenix routes through OAuth authorization redirects,
callback, issue reads, and disconnect. They substitute GitHub HTTP responses
under the actual Connect clients. Each HTTP fixture expects the exact
repository and token for that instance. Cross-repository calls fail before
HTTP dispatch. The tests check that the turn context carries a binding
reference and contains neither fixture token. They also check that a callback
requires its originating session and that it consumes state once.

The original CLI is still available with `./connect-bot`. It uses the local
GitHub CLI session. The Phoenix app uses its own OAuth client.

## Proposed Jido Connect Phoenix SDK

Connect owns `AccountSetup` and `CredentialResolver`. The GitHub package
implements the setup callbacks. The spike shows a host-owned callback and two
storage choices. An optional Phoenix adapter can package the route and store
integration shown here.

- **Provider contract.** A provider supplies OAuth capabilities, authorization
  URL construction, code exchange, grant normalization, and refresh or
  revocation where supported. GitHub already supplies code exchange and user
  connection helpers. API-key providers would use a separate credential
  submission flow and return the same connection and lease contracts.
- **Explicit Phoenix routes.** Give every mounted provider and flow a stable,
  host-selected route. For example, use
  `/integrations/github/oauth/callback` for GitHub user consent and
  `/integrations/google/oauth/callback` for Google. A GitHub App installation
  callback can have its own route. Resolve the absolute redirect URI from
  endpoint configuration and send the same URI in authorization and token
  exchange. Register the exact URI with the provider.
- **Shared callback handling.** The adapter starts a short-lived transaction
  bound to the signed-in user, tenant, provider, auth profile, OAuth client,
  redirect URI, and allowed return path. The callback consumes it once and
  verifies these bindings before code exchange. The provider can supply
  PKCE or other protocol requirements. The host supplies transaction and
  credential stores, permission checks, and its own UI.
- **Execution contract.** Generated actions use the host resolver to authorize
  the binding and obtain a fresh lease. The host resolves the token only after
  it checks the operation and resource. Connect then checks the lease, scopes,
  and policy before dispatch. An expired or revoked grant can return a
  reconnect error the Phoenix app can display.

For the first SDK iteration, keep the routes in the host router. A thin Plug or
controller helper can perform the shared callback steps and leave route naming,
storage, and consent UX in the host.
