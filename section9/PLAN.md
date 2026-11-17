# Section 9: Persistent Repair Team

## Goal

Build one local demo in which three persistent cognitive actors repair a small
Elixir fixture, survive an interrupted implementer, and keep enough committed
evidence to explain the result.

The actors are:

- Lead: creates and assigns work, observes evaluation evidence, and closes the
  mission only after the evaluator passes the candidate.
- Implementer: claims the repair task, changes only the writable fixture, and
  submits a candidate artifact.
- Evaluator: reads the candidate and protected acceptance tests, records pass
  or rework evidence, and cannot change the candidate.

This spike is separate from Jarvis and Alice. It does not change their files,
database, memory, or runtime.

## Verified Alice reuse boundary

The current Alice code starts a fresh Jido ReAct agent for each pulse. It
renders a bounded typed state, recalls memory, requests a structured proposal,
validates that proposal, stages write effects, and exposes streaming and audit
fields. Its current cycle directly depends on `Jarvis.Memories`,
`Jarvis.Alice.Agent`, and Jarvis review tools. It is not a generic persistence
engine, and its memory writes are not an atomic task-ledger commit.

Section 9 will reuse the design boundary, not Alice modules:

1. Load committed actor state and relevant ledger facts.
2. Render bounded role context.
3. Run one fresh ReAct request through a model adapter.
4. Validate one typed proposal.
5. Commit state and work changes in one ledger transaction.
6. Publish the committed event after the transaction.

This avoids a copied Alice implementation and avoids a dependency on the
Jarvis web server. The Section 9 cycle is a small spike-local engine with role,
model, and ledger adapters.

## Compatibility boundary

The implementation adds only `spikes/section9`. It does not change a public
Jido API. Section 9 pins the local `jido_vsm` repository's `release/v3` commit
`fa7f0d8` through a local Git dependency. The `jido_vsm` worktree is not
changed. No cross-package release order is required for this local spike.

## Viable Work Cell extension

The first fractal core is a native `Jido.VSM.Cell` with two S1 operations,
`delivery` and `learning`, and the standard S2, S3, S3*, S4, and S5 roles. One
typed work contract passes through the complete VSM signal cycle before the
existing repair team can run. S3* verifies both operational claims and S3
commands. The repair evaluator then performs the domain check.

The public loop reports `purpose`, `sense`, `decide`, `authorize`, `act`,
`verify`, `remember`, and `escalate`. A pain signal goes through the VSM
control and policy roles. An emergency signal stops the effect before repair
work starts. Jido holds activation state in ETS for this spike. The repair
ledger and evidence remain durable in SQLite.

The human engagement model separates the prescribed task from discretionary
work. A task states quantity, quality, target completion time, resources,
authority, accountability, discretion scope, and escalation conditions. The
human remains accountable, decides whether to delegate, and reviews the cell
evidence. The deterministic simulation records each human judgment without
claiming to model private human reasoning.

## Smallest complete architecture

### OTP runtime

- `Section9.Supervisor` starts the SQLite ledger, event registry, dynamic actor
  supervisor, and three stable actor processes.
- Each actor is a `GenServer` with a stable role identity. Its process state is
  a cache only. Committed state is loaded from SQLite for every pulse.
- An actor process may crash during a pulse. The supervisor starts it again
  with the same identity. A new claim generation makes earlier results stale.

### Durable ledger

Use SQLite with explicit transactions and these logical records:

- missions and mission budget
- tasks, owner, lease, claim generation, and legal status
- actor state and state revision
- pulses with rendered input, state before and after, output, and status
- candidate artifacts with source, diff, digest, and claim generation
- evaluations with command results and acceptance evidence
- effects with idempotency key and reconciliation status
- append-only events

Legal task transitions are:

`pending -> claimed -> candidate_ready -> evaluating -> passed -> closed`

Rework uses `evaluating -> rework -> claimed`. Lease recovery uses
`claimed|candidate_ready|evaluating -> claimed` with a new generation. A task
cannot close without a passing evaluation for its current candidate.

Every write effect has a stable idempotency key. Duplicate delivery returns the
stored receipt. A stale claim generation cannot publish a candidate, complete
work, or overwrite newer state. The demo claims at-least-once retry with
reconciliation. It does not claim exactly-once external execution.

### Cognitive pulse

One shared cycle module handles all roles:

1. Receive a manual or automatic pulse.
2. Load actor state, task facts, private role memory, and the mission budget.
3. Render a bounded model input from centralized role prompts and tool policy.
4. Call a configurable model adapter with time, model-call, tool-call, pulse,
   and mission limits.
5. Stream provisional text separately from committed results.
6. Validate the structured role proposal.
7. Apply permitted effects and the complete replacement state in one database
   transaction.
8. Publish committed events.

The UI calls the same pulse function in step and automatic modes. Model input
and state changes are inspection data. They are not hidden model reasoning.

### Repair fixture

The fixed fixture contains a small GenServer with a cancellation and late-result
bug. The starting source fails protected tests. The implementer can write only
the fixture source. Acceptance tests are stored outside that writable path.

Acceptance covers:

- normal request completion
- cancellation reply and cleanup
- late result after cancellation
- duplicate result delivery
- regression behavior after a canceled request

Concurrency tests use references and explicit messages, not sleeps.

### Model adapters

- `FakeModel` returns deterministic proposals for automated tests.
- `LocalModel` uses the configured LM Studio OpenAI-compatible endpoint and one
  stable small model. It has explicit request and total timeouts.
- The role tools are narrow ledger and fixture operations. The evaluator has no
  write tool for candidate source and cannot waive a failed command.

The first slice uses one model. It does not route models or adapt the team.

### LiveView

The development UI shows:

- three roles and their latest bounded state
- mission and task status
- owner, lease, and claim generation
- provisional stream output versus committed pulse results
- exact rendered input and state before/after
- shared event timeline
- candidate diff and evaluator command evidence
- step and automatic controls
- a development-only implementer interruption control

## Implementation sequence

1. Create the isolated Mix/Phoenix project and SQLite schema.
2. Implement ledger transitions, transactions, idempotency, claims, and
   recovery.
3. Add the fixed fixture and protected deterministic acceptance runner.
4. Add actor supervision, the shared pulse engine, bounded state, prompts,
   policies, and deterministic fake model.
5. Add LM Studio adapter through the Jido ReAct request path.
6. Add the LiveView and development interruption control.
7. Test the ledger and recovery before running a complete fake mission.
8. Run one real local-model mission.
9. Reset to the same fixture, interrupt the implementer after candidate save,
   and run the real recovery mission.
10. Record configuration, commands, pulse counts, elapsed time, intervention,
    and limitations in `RUNS.md`.

## Required checks

- Unit tests: legal transitions, role permissions, protected fixture scope,
  stale-result rejection, duplicate idempotency delivery, budget limits, and
  lease recovery.
- Integration test: deterministic fake model completes the mission.
- Recovery test: crash after candidate save and before completion, restart,
  reconcile, reject stale completion, and close only after evaluation passes.
- Live run: complete one mission through LM Studio.
- Interrupted live run: repeat from the same starting snapshot and verify safe
  recovery.
- Web check: LiveView renders committed and provisional evidence separately.
- Final repository check: only `section9` changes are new from this work.

## Deferred work

This slice does not include dynamic hiring, learned-skill promotion, model
routing, adaptive teams, a corporation DSL, distributed clustering, or a claim
that three actors outperform one actor.
