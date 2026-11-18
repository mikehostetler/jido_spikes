# Kura

Kura is a Phoenix spike for the Durable Work Cell in the Jido Work System.
Open [Work cells](http://127.0.0.1:4000/cells) to inspect a workspace, ask a
cell about its work, or save a memory.

## Run locally

Use Elixir 1.19 or later, a sibling Jido workspace checkout at
`../../jido_workspace/jido_workspace`, and GitHub SSH access to
`mikehostetler/jido_vsm`. Jido and AshJido use their V3 release branches.
The lock file records their exact revisions and the pinned VSM revision.
Keep the sibling Loom and HTN checkouts in the Jido workspace. HTN must
include its Catalog-backed domain codec.

```sh
mix setup
mix phx.server
```

The development server listens on loopback. Kura has no authentication.
The databases are `db/kura_dev.db` and `db/kura_test.db`. The development
workspaces use separate directories under `db/workspaces`.

## Run the local maintenance case

Run `mix ecto.migrate` if you already have a development database. Open
[Maintenance](http://127.0.0.1:4000/maintenance) and load the failed CI
fixture. Set `KURA_CELL_MODEL=openai:gpt-6.1-terra` and supply
`OPENAI_API_KEY` when you start Phoenix to give Cedar a ReAct turn when
CI reports a result, when Review replies, and when a case closes. Cedar
can call `use_playbook` to select the approved CI triage playbook.
Without a model, the local demo selects the approved playbook automatically.

For a learning run, start with the detailed failed CI fixture. Version 1
asks Review even when CI has the assertion. Complete the case. At closure,
Cedar can call `propose_playbook_edit` to propose a new HTN method condition.
Use **Replay fixtures** to compare the candidate with its baseline, then
**Approve** to activate a passing candidate. Select **Load detailed CI failure**
to see the new method use CI evidence. Select **Load CI failure summary** to see
Loom ask Review for the missing assertion. Restart Phoenix while it waits,
then select **Deliver Review reply** to resolve that same wait.

Load the new commit, the stale pass, and the new-head pass in order. The
case only closes when CI passes on the tracked head and that head differs
from the original failed commit. SQLite holds the case history, pulse
inbox, ReAct traces, and pending handoff. A case update and its new
inbox entries commit together. On startup, Kura recovers queued entries
and pending handoffs. It also imports queued pulses from older case records.
An interrupted model call can run again after its cell stops. Kura records
one result per pulse. Cedar saves the Loom run ID, wait ID, and request
before contacting Review. Review retries temporary failures. If triage
fails or Review runs out of attempts, the case shows **Blocked**.

Open **Run details** for pending pulse IDs, **Cedar's assessments** for
completed traces, and **Evidence details** for Jido VSM receipts.

## Exercise the cells

Open [Work cells](http://127.0.0.1:4000/cells), select Pine, and run
**Inspect workspace**. The same inbox and worker that process Cedar's
maintenance pulses run Pine's inspection. Pine uses its own role, workspace,
and read-only tool. Its command history shows the result and, when Terra runs,
the saved tool trace.

Pine also has a **Workspace observation playbook**. Select **Create a draft**
to read the workspace and save a template-based HTN draft. Select **Replay
fixture**, then **Approve**. Select **Run approved playbook** to record the
digest of the current brief using that saved version.

A cell module maps event kinds to handlers with `pulse_handlers/0`. Each
handler supplies the prompt, evidence, and tools for its task. A cell can
declare playbook tasks with `playbook_tasks/0`. A task supplies its trigger,
input validation, trusted action references, and fixture replay. The Cell
runtime drains one entry at a time and waits for a signal when its queue
is empty.

From the Kura directory, run:

```sh
mix ecto.migrate
mix run scripts/exercise_cells.exs
```

The script inspects all three workspaces, saves a note, and chats with
`cedar/review`. It prints the work results and each cell's bus events. Each
run adds entries to the development journal. Open or reload
[Work cells](http://127.0.0.1:4000/cells) on the Phoenix server to see the
entries. The script runs in a separate VM, so its live notifications stay
in that VM.

To use GPT-6.1 Terra with an `OPENAI_API_KEY` assignment in the local
`.env` file, run:

```sh
OPENAI_API_KEY="$(sed -n 's/^OPENAI_API_KEY=//p' .env)" \
KURA_CELL_MODEL=openai:gpt-6.1-terra mix run scripts/exercise_cells.exs
```

Use the same environment assignments with `mix phx.server` to enable the
model in LiveView.

## Define and run a cell

[`Kura.Cells.Cedar`](lib/kura/cells/cedar.ex) defines Cedar and its Review
slot. [`Kura.Cells.Inspector`](lib/kura/cells/inspector.ex) runs as both
`cedar/review` and the independent cell `pine`.

- **Capabilities** grant access to the workspace read and digest steps. Each
  instance mounts its own local directory with a read-only Jido Workspace
  policy. The spike supplies one inspection playbook.
- **Definition** includes a `ROLE.md` reference, skill names, signal bindings,
  seed memories, playbook steps, and child slots. `cell do` and the native
  `vsm do` contribute to the same Jido Agent definition.
- **Data** includes workspace files, commands and outcomes, chat turns, and
  operator notes. Ash stores the journal in SQLite using the cell ID.

`Kura.Cells.command("cedar/review", :inspect)` records a command and wakes
the cell. Native VSM control issues a delivery command with the same
correlation ID. The worker runs the playbook, records the result, and waits
for its next input. Startup resumes queued work. Chat has a separate entry
point, `Kura.Cells.chat/2`, and reads work status. Each active cell has its
own Jido Signal bus, available through `Kura.Cells.bus/1`. SQLite is the
durable journal.

The local demo uses a deterministic inspection and status reply. Set
`KURA_CELL_MODEL` to enable a bounded ReAct turn for work and chat. During
work, the model can choose one call to `read_workspace_brief`. It reads
`/brief.txt` in the selected cell and returns the byte count, content status,
and SHA-256 digest. The dashboard shows the recorded call and result in
**Latest run** and **Run history**. If the model skips the call, the run
marks the workspace unverified. Chat has no workspace tools.

Set `KURA_SKILL_ROOT` to a trusted directory containing `jido/SKILL.md`,
such as WorkTutor's `kata/skills` directory, to give the work turn the
declared Jido skill instructions.

## Import a cell definition from JSON

```sh
mix ecto.migrate
mix kura.cell.import priv/cells/examples/pine-data.json
```

Reload **Work cells** and select **Pine from data** or its **Pine check**
child. They each use a separate brief, bus, inbox, and command history.
The parent can also draft, replay, approve, and run a workspace observation
playbook.

The JSON file defines the cell tree, role text, seed memories, skills,
capabilities, workspace seed, signals, and bindings to handlers and tasks.
Choose `"cognition": "local"` for deterministic execution or
`"cognition": "inherit"` to use the model configured on the server.
Kura checks the bindings and saves each cell as a Jido Agent Codec document
in SQLite. An import creates new IDs. It rejects existing IDs and saves the
cell tree in one transaction.

The spike supplies a standard VSM topology, a read-only local workspace,
and a registry of approved handlers and tasks. A definition can select
those components. Elixir implements the components and Cedar's exact-commit
CI rule. Learned HTN versions and work history use separate SQLite records.

## Export the definition

Jido Catalog discovery registers the compiled definitions and their trusted
references. Write the definition in the Elixir DSL, then export
it with Jido Codec from a running IEx session.

```elixir
{:ok, json} = Kura.Cells.export_definition("cedar")
{:ok, definition} = Jido.Codec.decode_json(json, codec: Jido.Agent.Codec)
{:ok, profile} = Kura.Cell.profile(definition)
```

The document holds the canonical Agent definition. An imported definition
contains its role text. A compiled definition refers to a role file. Skill
references resolve to local files. Work history and workspace changes belong
to the cell instance.

## Checks

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```
