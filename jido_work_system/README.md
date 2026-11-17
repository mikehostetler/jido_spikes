# Jido Work System Spike

This project is a local simulation environment for a generalized Jido Work System. It tests a cohesive data model before production infrastructure exists.

The current resource model is a spike, not the selected production core. Start with the [design documents](docs/README.md) for confirmed product decisions, proposed replacement work, and pressure-test evidence.

## Run the project

```sh
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000). Choose one of these scenarios:

- **Straight-through release** shows a verified task from definition through human acceptance.
- **The missing risk section** stops after failed verification so the human can request revision or end the run.

The play view has **Step**, **Play**, **Pause**, and **Restart** controls. The PixiJS office stage shows task handoff, work, evidence delivery, verification, rework, and acceptance. Required controls and narration stay in HTML. The stage uses reduced motion when the browser requests it.

Each scenario run has its own URL. Use **Open debug view** to inspect the Ash resources and event timeline for that same run. Reloading the play view rebuilds the stage from persisted server state.

## Headless traces

Run one story without a browser:

```sh
mix work.trace --scenario straight-through-release
mix work.trace --scenario missing-risk-section --choice request_revision --output tmp/rework.json
```

Pressure test the work system with many saved runs:

```sh
mix work.pressure --runs 100
mix work.pressure --runs 100 --output tmp/summary.json --trace-dir tmp/traces
```

Each trace records every step, action, event, object count, and rule problem. The pressure runner uses all visual and headless stories. It also uses both choices for the story with a missing part. A pressure run fails when any trace breaks a work rule.

The pressure set also has 12 headless-only stories:

- clarification before work;
- a work cell that declines a job;
- missing facts that Mike supplies;
- one added permission;
- a failed tool with a safe retry;
- a delayed checker;
- an owner who cancels work;
- a missed deadline;
- a late change to the job;
- a smaller specialist cell;
- a second failed check; and
- passed work that the owner rejects.

These stories do not appear in the visual story list.

You can also run the simulation without the web interface:

```sh
mix simulate
mix run priv/run_simulation.exs rework
```

Run the checks with:

```sh
mix test
npm test --prefix assets
mix assets.build
mix ash.codegen --check
mix format --check-formatted
mix compile --warnings-as-errors
```

`mix precommit` runs the complete local gate, including Elixir tests, JavaScript tests, the asset build, and the Ash code generation check.

SQLite data, migrations, and Ash resource snapshots are under `db/`. Runtime database files are local and ignored by Git.

## Model boundary

The Ash domain contains first-class resources for:

- the work system, human actors, roles, authority, and accountability;
- recursive viable work cells, tasks, work executions, and delegations;
- judgments, judgment methods, and the decisions that result from judgments;
- authorized mutations and their receipts;
- evidence, evaluations, outcomes, tools, workspaces, knowledge, and events.

The task record keeps purpose, required output, quantity, quality, target completion time, resource limits, discretion limits, escalation conditions, and the accountable actor.

The model keeps these distinctions:

- A task states the contract. A work execution records the work state.
- A judgment records the basis, uncertainty, and risk. A decision records the selected choice.
- Authority permits action. Accountability remains with the named human actor.
- Evidence is an independently checkable artifact. Confidence belongs to an evaluation.
- Verification checks the evidence. Human acceptance is a separate outcome decision.

The local `jido_vsm` package validates each simulated cell through `Jido.Vsm.Topology.CellSpec`. The spike does not start or copy the VSM runtime. Ash resources are the durable source of record.

## Deterministic simulation

The success path creates one task, delegates it, accepts it in a child work cell, selects an HTN-like planner, an authority rule, and a fixed simulated LLM result, applies a bounded mutation, records evidence, verifies it, and records human acceptance.

The rework path first records failed verification. The human requests rework. A hybrid judgment selects an authorized revision. New evidence passes verification, and the human accepts the revised outcome.

Both paths use fixed inputs and ordered event sequence numbers. The interactive runner writes one beat in each transaction. Its run revision rejects stale browser commands. PixiJS renders a versioned scene projection and never owns domain state. The paths do not call a paid model or an external service.

## What the spike proves

- The resource relationships can represent accountable, recursive work.
- A complete task contract can move through delegation, judgment, authorized mutation, evidence, evaluation, and acceptance.
- Different deterministic judgment providers can support one task.
- A tool path can be checked against a bounded workspace.
- Verification and human acceptance can remain separate.
- Success and rework paths can be inspected and repeated.
- Several saved scenario runs can exist without deleting each other.
- A browser can step, play, pause, reload, and inspect one durable run.

## What the spike does not prove

- Production authorization or security.
- Distributed execution, recovery, or concurrency control.
- Dynamic hiring or organization design.
- Real tool integrations or paid LLM behavior.
- A general workflow language.
- A user-authored scenario format or scenario editor.
- Free movement, pathfinding, physics, or multiplayer control.
- Full integration with the `jido_vsm` runtime.

This project has no authentication and is not for production use.
