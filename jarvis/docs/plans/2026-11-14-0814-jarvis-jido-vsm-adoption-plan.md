---
title: Adopt Jido VSM in the Jarvis agent
type: implementation-plan
date: 2026-11-14
last_reviewed: 2026-11-14
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Adopt Jido VSM in the Jarvis agent

## Goal Capsule

- Objective: Replace the local Jarvis VSM simulation with native Jido VSM role
  Agents without changing the current Jarvis user flows.
- Means: Extend `jido_vsm` with one static application Cell contract. Put that
  Cell under the main Jarvis Agent. Move control and intelligence work to the
  correct role Agents in safe stages. Remove the local VSM Plugin and loopback
  Bus after behavior parity.
- Authority: Future local source and test changes in `jido_vsm` and Jarvis only
  when separately authorized. This planning run changes only this plan. It does
  not authorize a commit, push, release, or remote change.
- Stop conditions: Stop if the Cell needs a second process runtime, if Jarvis
  policy must move into `jido_vsm`, if Memory extraction becomes required, or
  if the completed `jido_vsm` example work cannot receive a recoverable
  checkpoint before new package edits.
- Next executor: An Elixir engineer who can work in `jido_vsm` first and Jarvis
  second.

## Product Contract

### Summary

Jarvis must keep its current chat, schedule, memory, control, and UI behavior.
The internal VSM boundary must become a real Jido Agent topology. Generic Cell
composition belongs in `jido_vsm`. Jarvis policy, file operations, durable
control records, and status projections remain in Jarvis.

`Jido.Plugin.Timer` remains the only schedule owner. The Jarvis memory Plugin
and SQLite store remain local. Memory is still a possible later extraction,
but it is not part of this work.

### Problem Frame

The current `Jarvis.Plugins.VSM` is one state field and one route provider. Its
six VSM roles are labels. All role work runs in the main Agent process. The
local Bus sends control Signals from the main Agent back to that same Agent.
This shape proved Signal routing and application behavior, but it does not give
the roles separate process state, failure isolation, or work admission.

The local `jido_vsm` package now uses native Jido V3 topology. One Cell owns S1
operation Agents plus S2, S3, S3*, S4, and S5 Agents. This is the correct
runtime origin for VSM composition. The current Cell is still a fixed standard
example. It requires at least two operations, fixes all role modules and
connections, and calls its deterministic adapter after a request has already
reached S1. Jarvis cannot use this fixed flow for policy-before-work control.

### Actors

- A person uses Chat, Control, or Memories in the Jarvis LiveView application.
- `Jarvis.Agent` owns the application schedule, memory routes, public status,
  and the nested VSM Cell activation.
- The VSM role Agents perform policy, control, coordination, operation,
  verification, and intelligence work.
- Jarvis maintainers use the spike to test package boundaries before another
  extraction.
- `jido_vsm` maintainers own reusable Cell composition and VSM Signal
  conventions.

### Requirements

- **R1:** `Jarvis.Runtime.prompt/2`, `inform/2`, `pause/0`, `resume/0`, and
  `status/0` keep their caller-visible behavior. Status keeps its `:schedule`
  and `:vsm` keys and the current VSM fields, including `:transitions`.
- **R2:** `Jido.Plugin.Timer` stays on the main Jarvis Agent and remains the
  only owner of recurring schedule state and timer processes.
- **R3:** `Jarvis.Plugins.Memory`, `Jarvis.Memory.Store`, `Jarvis.Memories`,
  SQLite FTS5, and the Memories UI stay local to Jarvis. This work does not
  extract or redesign memory.
- **R4:** The main Jarvis Agent owns one nested native VSM Cell. S1, S2, S3,
  S3*, S4, and S5 run as separate Jido AgentServer processes in that Cell.
- **R5:** `jido_vsm` owns the static Cell composition contract. It does not own
  Jarvis policy, Ecto schemas, file operations, model calls, or UI state.
- **R6:** A control objective passes through S5 policy, S3 work control, S2
  coordination, S1 execution, S3* verification, and S5 completion. A false
  success claim cannot become a completed run.
- **R7:** A scheduled assessment becomes S4 intelligence input. Memory recall
  happens at the Jarvis boundary, and S4 receives explicit evidence. An
  assessment or information Signal does not authorize S1 work.
- **R8:** Long or failed S1 work does not block the main Agent schedule, status
  calls, memory routes, or unrelated role Agents.
- **R9:** Existing Ecto control runs, trace events, resource leases, and
  PubSub updates remain the durable application record. Role Agent state is an
  operational projection, not the durable business result.
- **R10:** Current Chat, Control, and Memories pages keep their current user
  behavior. The Control page shows the real Cell roles instead of a static
  local role list.
- **R11:** The old Jarvis VSM Plugin, VSM record Directive, control Action, and
  loopback Bus leave the active source only after all callers use the Cell. A
  compatibility `:transitions` value remains in the Status projection and has
  no control authority.
- **R12:** The new `jido_vsm` contract uses only Jido V3 Agent, topology,
  activation, Signal, and ownership primitives. It adds no custom VSM
  supervisor, registry, PID map, or routing GenServer.
- **R13:** Existing `Jido.VSM.Cell` standard behavior and examples remain
  valid while the application Cell form is added.
- **R14:** Both repositories pass their supported compile, format, unit,
  integration, and example gates at the final integration state.

### Key Flows

Control objective:

```text
Control.run
-> main Jarvis Agent
-> nested VSM Cell root
-> S5 policy decision
-> S3 current-work control
-> S2 resource lease
-> S3 assignment
-> S1 file operation
-> S3* actual-state verification
-> S5 terminal run record
-> Ecto and PubSub result
```

Scheduled assessment:

```text
Timer occurrence
-> main Agent validates current schedule generation
-> local Memory Plugin recalls evidence
-> VSM Cell root
-> S4 assessment
-> assessment result event
-> main Agent status projection
```

Information:

```text
Runtime.inform
-> main Agent validation
-> VSM Cell root
-> S4 observation
-> bounded observation result event
-> main Agent status projection
```

### Acceptance Examples

1. A person starts a purpose, sees repeated assessments, pauses the schedule,
   and resumes it with the same purpose. Timer state stays on the main Agent.
2. A matching memory ID reaches S4 as evidence for an assessment. S4 does not
   call SQLite directly.
3. A valid objective writes the requested file and finishes only after S3*
   reads and verifies the file.
4. A false S1 success report produces `repair_required`, not `completed`.
5. Two objectives for one resource produce one active lease and one explicit
   resource conflict.
6. A blocked policy request stops before S1 receives an assignment.
7. An S1 Action that waits does not prevent `Jarvis.Runtime.status/0` from
   returning or Timer from delivering an assessment to S4.
8. Killing one VSM role Agent restarts that role without replacing the main
   Jarvis Agent or unrelated role Agents.
9. Chat tools still address the same main Agent. The conversation Agent stays
   separate.
10. The final main Agent has Timer, local Memory, and a small status projection.
    It has no local VSM Plugin or loopback Bus.

### Success Criteria

- The standard `jido_vsm` Cell and one custom one-operation Cell both pass
  package integration tests.
- Jarvis control and assessment behavior passes through separate role Agents.
- Main Agent status remains responsive during blocked S1 work.
- Existing durable control and memory records remain compatible.
- Current LiveView tests pass without a user-facing workflow change.
- Source checks find no active local VSM Plugin or internal loopback Bus after
  cutover.

### Scope Boundaries

In scope:

- A static, compile-time application Cell form in `jido_vsm`.
- One or more S1 operations, including a valid one-operation Cell.
- Application-selected role Agent modules, initial state, Cell ports, and
  internal connections.
- A nested Jarvis VSM Cell with Jarvis-owned role Actions.
- Control and assessment migration to the Cell.
- A small main-Agent status projection for caller compatibility.
- Removal of the local VSM Plugin and loopback Bus after parity.
- Process isolation, retry safety, and local restart tests.

Out of scope:

- Memory extraction, embeddings, vector search, or a memory schema change.
- Timer changes in Jido core.
- Dynamic VSM topology, live role replacement, or live adapter hot-swap.
- Network transport, distributed cells, or multi-node coordination.
- A durable outbox or exactly-once Signal delivery.
- Atomic snapshots of all role Agents.
- Autonomous model-based capability selection.
- New Jarvis capabilities beyond the current file-operation proof.
- A database migration unless implementation evidence proves that the existing
  run, trace, and lease records cannot support retry safety.
- Commit, push, pull request, release, or publication.

### Key Decisions

- Keep `Jarvis.Agent` as the application shell and activation root.
- Put one native VSM Cell below the main Agent instead of turning the main
  Agent into a VSM Cell.
- Keep package composition generic and keep application behavior in Jarvis.
- Treat scheduled assessment as S4 intelligence, not an S1 operation.
- Keep Ecto records authoritative for control results.
- Use static topology connections for internal delivery. Do not keep the local
  Bus only to send a Signal back to the same activation tree.
- Use an expand, migrate, and remove sequence. Do not delete the local VSM path
  before both control and intelligence use the Cell.

### Rejected Alternatives

- Keep all roles inside `Jarvis.Plugins.VSM`: long S1 work continues to block
  the main Agent, and the role boundary remains only a label.
- Turn `Jarvis.Agent` into `Jido.VSM.Cell`: this makes the Cell macro own the
  root definition and complicates Timer, Memory, schedule routes, and Chat
  tool compatibility.
- Put Jarvis policy and Ecto code in `jido_vsm`: this would make the package an
  application package instead of a reusable VSM composition package.
- Use only the completed custom adapter option: the current adapter callbacks run
  inside a fixed S1-first graph. They cannot express policy-before-work,
  resource leasing, or Jarvis-specific role routes.
- Treat assessment as a second S1 operation: assessment is intelligence work
  and must not gain operation authority.
- Keep the Bus as an internal relay: native topology already owns delivery
  between declared Agents.
- Extract Memory in the same change: the local Memory boundary is useful and
  has not yet produced enough evidence for a stable package contract.
- Replace Ecto control records with Agent state: this would reduce durability
  and make restart recovery less clear.

### Dependencies

- The local Jido core dependency in both projects.
- The local `jido_vsm` package at commit `a67f651` plus its completed,
  uncommitted example-roadmap work.
- The completed `jido_vsm` example-roadmap plan, which added adapter selection,
  lifecycle examples, `CellGroup`, and `DynamicCell`.
- Existing Jarvis Timer and Memory boundaries.
- Existing Jarvis Ecto control records and filesystem policy proof.

### Outstanding Questions

None block this plan. The completed `jido_vsm` worktree passes its final gates,
but it is not committed. The executor must make a recoverable checkpoint or
use a separate worktree before U1 edits package source. This is an execution
precondition, not a product decision.

### Sources

- [Jarvis README](../../README.md)
- [Jarvis main Agent](../../lib/jarvis/agent.ex)
- [Jarvis local VSM Plugin](../../lib/jarvis/plugins/vsm.ex)
- [Jarvis control Action](../../lib/jarvis/actions/vsm.ex)
- [Jarvis assessment Action](../../lib/jarvis/actions/assess_purpose.ex)
- [Jarvis durable workflow](../../lib/jarvis/control/workflow.ex)
- [Jido VSM Cell](../../../../jido_workflow/jido_vsm/lib/jido_vsm/cell.ex)
- [Jido VSM architecture](../../../../jido_workflow/jido_vsm/docs/v3-architecture.md)
- [Jido VSM example-roadmap plan](../../../../jido_workflow/jido_vsm/docs/plans/2026-11-14-0810-example-roadmap-plan.md)

## Planning Contract

### Product Contract Preservation

Product Contract unchanged. The plan changes process ownership and package
placement. It preserves current Jarvis caller behavior, stored record meaning,
policy, and UI flows.

### Current System

`Jarvis.Agent` is one activated application Agent. It loads local Memory and
VSM Plugins, core Timer, and the Jido Bus DSL. The main Agent has no child role
Agents. The Bus has paired root-to-Bus and Bus-to-root connections for each
control, assessment, and information Signal.

`Jarvis.Plugins.VSM` owns one `:vsm` state map. The map contains assessment
counts, observations, the last assessment, and a control transition count.
`Jarvis.Actions.VSM` maps Signal type strings to policy, lease, file, verify,
and finish functions. All these calls run inside main-Agent turns.

The control context stores runs, trace events, and resource leases in SQLite.
The file write and SQLite calls happen before the Agent turn commits. The
trace uniqueness rule makes repeated trace positions harmless. Lease acquire
does not yet treat a retry by the same run as success.

Timer state and production now have a clear core owner. The Jarvis assessment
Action validates Timer occurrence generation. The local Memory Plugin recalls
SQLite evidence through prepared Plugin configuration. These boundaries are
sound and do not need extraction in this work.

The standard `jido_vsm` runtime unit is one native Jido V3 Cell. Its Cell
creates separate role Agents and uses native topology only. The current macro
fixes the role modules and standard connection graph. It requires two or more
S1 operations. The completed roadmap work added a literal `:adapter` option,
put the selected adapter in role state, and changed standard Actions to read
that adapter. It also added a static `Jido.VSM.CellGroup` and
`Jido.VSM.DynamicCell` ownership helpers. These are useful package contracts,
but Jarvis needs one declared Cell, not a group or a dynamic attach operation.
None of these additions changes the fixed S1-first graph. The standard flow
sends an external request to S1 before S5 can apply an application policy
decision.

The completed `jido_vsm` work remains uncommitted above local commit `a67f651`.
It has 11 offline integration examples. This plan must preserve that work and
must not mix it with U1 without a recoverable checkpoint.

Current verification evidence on 2026-11-14:

- Jarvis compile, format, and all 31 tests passed.
- The completed `jido_vsm` worktree passed format, compile with warnings as
  errors, 17 package tests, and all 11 example tests.

The final examples prove native containment, stable nested identity, member
failure isolation, per-Agent persistence boundaries, trace and causation,
static Cell groups, dynamic local ownership, and pure adapter selection. They
do not prove Jarvis policy, leases, file effects, status projection, or a
policy-before-operation flow. Integration therefore reuses the Cell ownership
model but does not put Jarvis side effects in an adapter.

Direct adoption has four exact gaps:

| Completed package contract | Jarvis requirement | Integration decision |
| --- | --- | --- |
| At least two standard S1 operations | One current workspace operation | Add a one-or-more application Cell form; do not invent a second Jarvis operation |
| External request reaches S1 first | S5 policy must run before S1 work | Use application-selected role Agents and connections |
| Adapter calculates pure decisions | Ecto leases and filesystem effects | Keep effects in Jarvis role Actions |
| CellGroup and DynamicCell own complete Cells | One Cell has the same lifetime as `Jarvis.Agent` | Use one declared nested Cell; use neither helper |

### Target System

The main activation tree becomes:

```text
Jarvis.Agent
├── plugins
│   ├── Jarvis.Plugins.Memory
│   ├── Jarvis.Plugins.Status
│   └── Jido.Plugin.Timer
└── topology
    └── vsm: Jarvis.VSM.Cell
        ├── workspace: Jarvis.VSM.Agent.Workspace (S1)
        ├── s2: Jarvis.VSM.Agent.Coordination
        ├── s3: Jarvis.VSM.Agent.Control
        ├── s3_star: Jarvis.VSM.Agent.Audit
        ├── s4: Jarvis.VSM.Agent.Intelligence
        └── s5: Jarvis.VSM.Agent.Policy
```

`Jarvis.Chat.Agent` stays separate. `Jarvis.Agent` remains the address used by
Chat tools and the public Runtime API.

`Jido.VSM.Cell` gains this static application form as design guidance:

```elixir
use Jido.VSM.Cell,
  name: "jarvis_vsm_cell",
  operations: [
    workspace: {Jarvis.VSM.Agent.Workspace, %{operation: "workspace"}}
  ],
  roles: [
    s2: {Jarvis.VSM.Agent.Coordination, %{}},
    s3: {Jarvis.VSM.Agent.Control, %{}},
    s3_star: {Jarvis.VSM.Agent.Audit, %{}},
    s4: {Jarvis.VSM.Agent.Intelligence, %{}},
    s5: {Jarvis.VSM.Agent.Policy, %{}}
  ],
  ports: [
    {:in, "jarvis.control.objective.requested", :s5},
    {:out, "jarvis.control.completed", :s5}
  ],
  connections: [
    {"jarvis.control.objective.authorized", :s5, :s3}
  ]
```

The application form uses a keyword list for named S1 members. Each member and
role value is `{agent_module, initial_state}`. `roles` has exactly the five
keys in the example. Each port is `{direction, signal_path, role}`. Each
internal connection is `{signal_path, from_role, to_role}`. All values are
literal compile-time data.

For an inbound port, the macro adds a Cell-root forwarding route and a
root-to-role connection. For an outbound port, the macro adds a role-to-root
connection and a Cell-root forwarding route so the enclosing topology can
connect that Cell output. One path cannot be both inbound and outbound in the
same Cell. Internal connections do not pass through the Cell root.

The current atom-list syntax remains the standard Cell shorthand and keeps its
current behavior. The atom-list and keyword-list forms are mutually exclusive
shapes of `operations`.

Jarvis does not use `Jido.VSM.CellGroup` because the application has one VSM
Cell. It does not use `Jido.VSM.DynamicCell` because `Jarvis.Agent` owns the
Cell for its complete activation. The new application form extends Cell
definition only. It does not duplicate either helper.

Jarvis role Actions use the existing `Jarvis.Control.Policy` and
`Jarvis.Control.Workflow` modules. The Actions emit traced Signals between role
Agents. The package does not call Jarvis modules.

The main Agent status Plugin is a small event projection. It stores the public
assessment, observation, and transition summary that `Jarvis.Runtime.status/0`
already returns. It does not make policy decisions or own role work. Ecto
remains the source for control run status. Transition events update the
compatibility count after role turns commit.

The compatibility checkpoint Signal is
`jarvis.vsm.compatibility.transition.committed`. Its data contains `run_id`
and one of the seven legacy checkpoint names: `strategy.requested`,
`objective.requested`, `assignment.issued`, `result.reported`,
`result.verified`, `verification.failed`, or `objective.stopped`. A role emits
the Signal only after it commits the matching checkpoint. Internal policy,
coordination, audit, trace, and forwarding Signals do not increment the public
count.

`Jarvis.VSM.Roles` keeps the Control UI text for each role: `id`, `system`, and
`authority`. The module joins that presentation data to the role membership in
the compiled Cell definition. `jido_vsm` does not own Jarvis UI text.

### Key Technical Decisions

#### KTD1 — Keep a shell Agent above the VSM Cell

- **Decision:** Keep `Jarvis.Agent` as the public Agent and declare
  `Jarvis.VSM.Cell` as one nested topology member.
- **Reason:** R1-R4 require stable Timer, Memory, Runtime, and Chat boundaries
  while role work gains process isolation.
- **Rejected alternative:** Make the main Agent itself use `Jido.VSM.Cell`.
  The current macro owns the root Agent definition and would mix application
  shell concerns with VSM role composition.
- **Consequences:** The Cell needs explicit inbound and outbound ports. The
  main Agent can restart or inspect the Cell through normal Jido topology
  ownership.
- **Governs:** R1-R4, R8, U2-U6.

#### KTD2 — Add one static application Cell contract to jido_vsm

- **Decision:** Extend the Cell macro with compile-time member, role, port, and
  connection data. Keep the current standard shorthand as a compatible preset.
  Allow one S1 member.
- **Reason:** R5, R12, and R13 require reuse without a custom runtime or a copy
  of the Cell macro in Jarvis.
- **Rejected alternative:** Put a callback-driven runtime profile manager in
  the package. The current Jido Agent DSL already owns lifecycle and routing.
- **Consequences:** Macro validation becomes a public contract. Invalid member
  modules, role names, paths, or endpoints must fail at compile time. Dynamic
  changes remain out of scope.
- **Governs:** R4-R6, R12-R14, U1-U2.

#### KTD3 — Keep behavior and effects in Jarvis role Agents

- **Decision:** `jido_vsm` supplies topology composition and common Signal
  conventions. Jarvis supplies role Agent modules, Actions, policy, Ecto calls,
  and filesystem work.
- **Reason:** R5 and R9 define a clean package boundary. The current standard
  adapter contract cannot express the Jarvis policy-first sequence by itself.
- **Rejected alternative:** Add Jarvis callbacks to the generic standard
  Agents. This would turn the package contract into a list of one application's
  side effects.
- **Consequences:** Jarvis keeps application code, but it removes the generic
  topology and role-lifecycle code. The current standard Cell stays useful for
  examples.
- **Governs:** R5-R9, U1-U4.

#### KTD4 — Use Ecto as the durable control authority

- **Decision:** Keep `control_runs`, `control_trace_events`, and
  `resource_leases` authoritative. Make role Actions safe for a repeated
  `run_id` and transition. Treat role Agent state as a local projection.
- **Reason:** R6 and R9 require correct results across asynchronous turns and
  local role restart.
- **Rejected alternative:** Make one role snapshot the only record of a run.
  Jarvis already has durable records and a UI built on them.
- **Consequences:** `Workflow.acquire/2` must accept an existing active lease
  owned by the same run. Terminal runs must ignore later duplicate work.
  File writes remain idempotent for the current exact-content proof. This plan
  does not claim exactly-once delivery. Committed role transition events also
  emit `jarvis.vsm.compatibility.transition.committed` for the seven named
  legacy checkpoints. The main Status projection consumes that Signal so
  `Runtime.status/0` keeps its current `:transitions` field. Ecto remains the
  authority for each run.
- **Governs:** R6, R8-R10, U2-U6.

#### KTD5 — Send prepared evidence to S4

- **Decision:** The main Agent validates the Timer occurrence and recalls local
  memory. It sends purpose, memory IDs, and bounded observations to S4. S4
  emits an assessment result. S4 does not authorize an operation.
- **Reason:** R2, R3, and R7 keep Timer and Memory ownership stable and place
  intelligence work in the correct role.
- **Rejected alternative:** Give S4 direct access to the Jarvis Memory Plugin.
  Plugin input and application store configuration belong to the main Agent.
- **Consequences:** The assessment Signal data becomes an explicit evidence
  contract. The main status projection updates from S4 output and can be
  eventually consistent by one Signal turn.
- **Governs:** R1-R3, R7, R10, U4-U6.

#### KTD6 — Remove the loopback Bus after Cell cutover

- **Decision:** Use declared topology connections for main-Agent-to-Cell and
  Cell-to-main-Agent delivery. Remove `Jido.Plugin.Bus.DSL` when no current
  external Bus consumer remains.
- **Reason:** R11 and R12 require one clear internal transport owner.
- **Rejected alternative:** Keep Bus and topology for the same internal paths.
  Two routing layers make ownership and failure evidence less clear.
- **Consequences:** Signal type and trace continuity must be tested across the
  nested Cell boundary before removal.
- **Governs:** R4, R7, R11-R14, U3-U6.

#### KTD7 — Use an expand, migrate, and remove sequence

- **Decision:** Add the package contract first. Add and test the Jarvis Cell
  beside the local VSM path. Move control, then intelligence and status.
  Remove the inactive old Plugin and Bus last.
- **Reason:** R1, R10, R11, and R14 need a checked result at each boundary.
- **Rejected alternative:** Replace all VSM code in one change. That would mix
  package API design, role semantics, persistence, and UI migration.
- **Consequences:** The temporary source can contain both implementations, but
  only one implementation may own each live Signal type during a migration
  unit.
- **Governs:** All requirements and U1-U6.

#### KTD8 — Keep Timer and Memory outside the VSM extraction

- **Decision:** Make no Timer change and no Memory package extraction. Change
  only the assessment handoff around those stable boundaries.
- **Reason:** R2 and R3 preserve the two boundaries already validated by the
  prior quality passes.
- **Rejected alternative:** Combine all candidate extractions in one effort.
  This would remove the consumer evidence needed to design Memory well.
- **Consequences:** The final Jarvis app still contains a local Memory Plugin
  and store behavior. This is deliberate.
- **Governs:** R2, R3, U2-U6.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| `jido_vsm` worktree | Commit `a67f651` plus completed uncommitted example work | Checkpoint the completed work before Cell changes | Do not overwrite or mix the completed work |
| `Jido.VSM.Cell` | Two or more atom operations, fixed role modules and graph | Add static custom members, ports, and connections; allow one S1 | Keep current shorthand and examples |
| Standard VSM adapters | One fixed pure adapter through role state | Preserve the completed roadmap contract | Do not put Ecto or filesystem effects in the adapter |
| Jarvis dependency set | Local Jido only | Add local `jido_vsm` path dependency | Both packages must resolve the same Jido source and Elixir version |
| `Jarvis.Agent` | Memory, local VSM, Timer, Bus; no child Agents | Memory, Status, Timer; one nested VSM Cell | Public Agent ID stays `jarvis-main` |
| `Jarvis.Plugins.VSM` | VSM state, route derivation, record Directive | Remove after both migrations | Status projection replaces only caller-facing summary state |
| Control flow | All roles execute in one Action on main Agent | Jarvis role Agents and traced Signals | Preserve Ecto run and UI shapes |
| Control durability | Ecto run, trace, lease; side effects in Agent turn | Add retry-safe role transitions | No exactly-once claim |
| Assessment flow | Main Agent recalls memory and writes local VSM state | Main Agent prepares evidence; S4 assesses; Status projects result | One-turn eventual projection |
| Information flow | Bus loopback records one observation | Direct Cell input to S4 plus result event | Information remains non-authorizing |
| Timer | Core Plugin state on main Agent | No ownership change | Nested role work must not block Timer delivery |
| Memory | Local Plugin and SQLite store | No extraction or schema change | S4 receives evidence, not store access |
| Runtime and Chat tools | Main Agent calls and `:schedule` plus `:vsm` status | Preserve all current fields through Status projection | Internal source of `:vsm` changes |
| Control LiveView | Static role list plus Ecto run trace | Join Cell membership with local `Jarvis.VSM.Roles` display metadata | User actions and run display stay stable; package stays UI-neutral |
| Local Bus | Internal root-to-Bus-to-root relay | Remove after topology parity | Keep only if a real external consumer is found |
| Tests | Assert no role Agent processes | Assert one Cell subtree and role isolation | Replace the old architecture assertion |

No stored-memory or control-table migration is planned. The implementation
must stop and revise this plan before it adds one.

### Implementation Units

#### U1 — Add the jido_vsm application Cell contract

- **Outcome:** `jido_vsm` can compile a one-operation Cell with
  application-selected role Agents, static ports, and static internal
  connections. The standard Cell remains unchanged.
- **Requirements:** R4-R6, R12-R14.
- **Dependencies:** None in this plan. The completed example-roadmap work must
  have a recoverable checkpoint before source edits begin.
- **Affected surfaces:** `Jido.VSM.Cell`, its compile-time validation, package
  structure tests, one custom Cell fixture, README, architecture guide, and
  migration notes. Reconcile the completed adapter-selection work rather than
  rewriting it.
- **Implementation direction:** First record the completed package baseline,
  including its adapter, CellGroup, DynamicCell, and 11-example contracts.
  Preserve them. Add the exact literal application form in Target System to
  the Cell macro. `operations` is a keyword list of
  `{agent_module, initial_state}` values. `roles` has exactly `:s2`, `:s3`,
  `:s3_star`, `:s4`, and `:s5` with the same value shape. A port is
  `{direction, signal_path, role}`. A connection is
  `{signal_path, from_role, to_role}`. Generate the inbound root-forwarding
  route and root-to-role connection, the outbound role-to-root connection and
  root-forwarding route, and direct internal role connections. Reject one path
  used as both an inbound and outbound port. Validate names, Agent definitions,
  path strings, endpoints, duplicate members, duplicate connections, zero S1
  members, and missing roles at compile time. Keep
  `operations: [:orders, :fulfillment]` as a mutually exclusive standard
  preset. Add no process, registry, or runtime module.
- **Test scenarios:** Existing standard Cell definition is equal before and
  after; one S1 is valid; zero S1 is rejected; missing or duplicate role is
  rejected; invalid Agent module is rejected; one inbound port reaches the
  selected role; one outbound role Signal leaves the Cell root; custom
  connections preserve trace and causation; current examples still pass.
- **Verification:** Run focused Cell and structure tests, then all package and
  example gates.
- **Completion signal:** A package-only custom Cell proves the full static
  extension without any Jarvis dependency or custom runtime.

#### U2 — Build and mount the Jarvis Cell beside the current path

- **Outcome:** Jarvis has one directly testable `Jarvis.VSM.Cell` with six
  Jarvis-owned role Agent definitions. The Cell is a dormant nested member of
  `Jarvis.Agent`, but current production Signal types still use the local VSM
  Plugin.
- **Requirements:** R3-R9, R12-R14.
- **Dependencies:** U1 supplies the application Cell contract.
- **Affected surfaces:** Jarvis dependency manifest and lockfile;
  `Jarvis.Agent` topology; new `Jarvis.VSM` Cell, role Agents, Signal
  contracts, and Actions; existing `Jarvis.Control.Policy` and `Workflow`;
  focused Cell tests. No LiveView or Runtime caller changes occur in this unit.
- **Implementation direction:** Add the local `jido_vsm` dependency. Define one
  `:workspace` S1. Use separate S2, S3, S3*, S4, and S5 modules. Keep policy,
  lease, file, verify, trace, finish, and PubSub functions in Jarvis. Use
  `run_id` as the application correlation key and preserve Jido trace and
  causation on every derived Signal. Make a repeated lease request by the same
  run idempotent. Make every role ignore a terminal run. Declare
  `agent(:vsm, Jarvis.VSM.Cell)` under `Jarvis.Agent`, but do not connect live
  control, assessment, or information Signal types to it yet.
- **Test scenarios:** Allowed objective completes after actual file
  verification; blocked policy never reaches S1; false success becomes
  `repair_required`; same-resource competition stops one run; repeated current
  transition does not duplicate a durable trace or stop its own lease; S4
  accepts explicit evidence but cannot emit an S1 assignment.
- **Verification:** Run the new Cell integration tests and the unchanged
  existing Jarvis suite.
- **Completion signal:** The resident but dormant Cell proves current control
  semantics in isolation while the live Jarvis path remains unchanged.

#### U3 — Move objective control to the nested Cell

- **Outcome:** `Jarvis.Control.run/2` keeps its API, but every live objective
  runs through the nested role Agents.
- **Requirements:** R1, R4-R6, R8-R10, R12-R14.
- **Dependencies:** U2 supplies the tested and mounted Jarvis Cell.
- **Affected surfaces:** `Jarvis.Agent` control ports,
  `Jarvis.Control`, main-Agent control routes, current control tests, and the
  Control LiveView role source. Add one temporary
  `Jarvis.Actions.ProjectLegacyVSMTransition`. The local VSM Plugin remains for
  assessment, information, and the public transition projection during this
  unit.
- **Implementation direction:** Connect objective input to the resident Cell
  root. Route terminal and trace
  output back only where the application needs a root projection or reply.
  Keep `Control.run/2` waiting on Ecto terminal state. Replace the old
  `Jarvis.Actions.VSM` ownership one transition at a time. Ensure one live
  owner for each control Signal type. Until U4 replaces the public projection,
  each role that commits one of the seven legacy checkpoints emits
  `jarvis.vsm.compatibility.transition.committed` with `run_id` and
  `checkpoint`. Add an explicit main-Agent route from that Signal to
  `Jarvis.Actions.ProjectLegacyVSMTransition`. That temporary Action reads the
  current `:vsm` projection and returns `Jarvis.Plugins.VSM.Record` with an
  incremented count. It performs no control work. Add local
  `Jarvis.VSM.Roles` presentation data for `id`, `system`, and `authority`.
  Join it to the compiled Cell membership for the Control page. Fail tests for
  a missing, extra, or unknown role.
- **Test scenarios:** Existing six control tests retain their behavior; the
  main Agent remains responsive while S1 holds work; resident Agents include
  the expected Cell subtree; one role failure does not stop the root or
  siblings; timeout returns current durable run state and does not report
  completion; each legacy checkpoint increments `:transitions` once; internal
  role Signals do not increment it; the temporary projection Action does not
  call policy, Ecto, or the filesystem.
- **Verification:** Run focused control, topology, LiveView, and concurrency
  tests, then the full Jarvis suite.
- **Completion signal:** No live objective uses `Jarvis.Actions.VSM`, and Ecto
  results match the pre-migration contract.

#### U4 — Move assessment and information to S4

- **Outcome:** Timer assessments and information observations run through S4.
  `Jarvis.Runtime.status/0` keeps the current public schedule and VSM summary.
- **Requirements:** R1-R4, R7, R8, R10, R13-R14.
- **Dependencies:** U3 supplies the live Cell path and role-transition events.
- **Affected surfaces:** `AssessPurpose`, `Information`, main Agent Cell ports,
  S4 Actions and state, a new small `Jarvis.Plugins.Status`, Runtime status,
  Chat status tool, Plugin tests, and assessment schedule tests.
- **Implementation direction:** Keep Timer generation validation and Memory
  recall on the main Agent. Send only prepared evidence to S4. Send reference
  information to S4 as an observation. S4 caps observations at 100 and emits
  assessment or observation result events to the main Agent. Replace the
  active local VSM Plugin provider with Status. Status projects assessment,
  observation, and committed role-transition events into every current `:vsm`
  field, including `:transitions`. Replace the temporary U3 route and Action
  with the Status route for the same compatibility checkpoint Signal. The
  projection owns no policy, operation, lease, or verification state. Leave
  the old Plugin source inactive for U5 removal. Do not let an assessment or
  observation type connect to S1, S2, or S3.
- **Test scenarios:** Repeated assessment, pause, stale occurrence rejection,
  resume generation, matching memory IDs, observation cap, information does
  not change memory, information does not start work, and blocked S1 does not
  block S4 assessment.
- **Verification:** Run assessment, Plugin, Chat tool, and schedule tests, then
  the full Jarvis suite.
- **Completion signal:** All live intelligence inputs use S4 and no assessment
  state is written by `Jarvis.Plugins.VSM`.

#### U5 — Remove the local VSM and loopback transport

- **Outcome:** Jarvis has one VSM implementation and one internal topology
  transport path.
- **Requirements:** R4-R5, R7, R10-R14.
- **Dependencies:** U3 and U4 move all live callers.
- **Affected surfaces:** Remove `Jarvis.Plugins.VSM`, its Record Directive,
  `Jarvis.Actions.VSM`, authoritative transition logic, derived routes, and
  paired Bus connections. Remove `Jido.Plugin.Bus.DSL` if repository search
  finds no real external consumer. Simplify `Jarvis.Plugins.Support` only when
  no remaining caller needs a helper. Update README and active plans.
- **Implementation direction:** Use source and compiled definition searches to
  prove that no route, Plugin provider, state field, or UI caller uses the old
  path. Keep the Status projection local. Do not move Memory or schedule code
  during cleanup.
- **Test scenarios:** Main Agent providers are Memory, Status, and Timer;
  topology has one VSM Cell; `:transitions` exists only in the Status
  compatibility projection; no root-to-Bus-to-root pair; public Runtime shape
  is unchanged; all user pages still render.
- **Verification:** Run removal searches, compiled Agent definition tests, and
  full repository gates.
- **Completion signal:** Old source is deleted, no active reference remains,
  and all behavior tests pass on the Cell path only.

#### U6 — Prove lifecycle and final integration

- **Outcome:** Both packages have current evidence for isolation, restart,
  trace, compatibility, and repository quality on one unchanged final state.
- **Requirements:** R1-R14.
- **Dependencies:** U5 supplies the final architecture.
- **Affected surfaces:** Cross-boundary integration tests, lifecycle fixtures,
  README and architecture documentation in both repositories, and final
  verification only. Change source only if a failed contract returns to its
  owning unit.
- **Implementation direction:** Prove root, Cell, and role lifecycle with
  public Jido APIs. Use Ecto to confirm terminal run meaning after a role
  restart. Prove Timer and S4 continue during blocked S1 work. Record the
  current ETS persistence limit. Do not claim VM-restart recovery or atomic
  Cell snapshots.
- **Test scenarios:** S1 kill and restore; sibling PID stability; main root
  survival; trace and causation across root, Cell, and roles; active Timer
  assessment during S1 wait; terminal duplicate rejection; all examples;
  current LiveView flows.
- **Verification:** Run the complete Verification Contract without source
  changes between gates.
- **Completion signal:** Every final gate passes, documentation matches the
  final source, and no risk is hidden as a durability claim.

### Work Graph

- Initial frontier: U1 after the completed `jido_vsm` work has a recoverable
  checkpoint or a separate worktree.
- Critical path: U1 -> U2 -> U3 -> U4 -> U5 -> U6.
- Migration order: U3 keeps the old projection current until U4 installs the
  Status projection. This prevents two owners for the same public state.
- Final integration unit: U6.

```text
U1 -> U2 -> U3 -> U4 -> U5 -> U6
```

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Standard Cell compatibility | U1 | Existing package and example tests | Current Cell behavior passes unchanged |
| Application Cell contract | U1 | Custom one-S1 compile and runtime tests | Static ports and role modules work |
| Jarvis Cell parity | U2 | Direct Cell integration tests | Policy, lease, execution, verify, and S4 contracts pass |
| Live control cutover | U3 | Existing and new control tests | Public run results match and roles are separate Agents |
| Intelligence cutover | U4 | Timer, Plugin, and Chat tool tests | Assessment and observation use S4 without authority leak |
| Removal | U5 | Source search and compiled Agent definition | No local VSM Plugin or loopback Bus remains |
| Lifecycle | U3-U6 | Block, kill, restart, trace, and causation tests | Root stays responsive and durable results remain correct |
| Jarvis UI | U3-U6 | Current LiveView tests | Chat, Control, and Memories flows pass |
| Package repository | U1, U6 | Supported `jido_vsm` gates | Package and all examples pass |
| Jarvis repository | U2-U6 | Supported Jarvis gates | Compile, format, and all tests pass |

Run from `/Users/mhostetler/Source/Jido/jido_workflow/jido_vsm`:

```sh
mix test
mix test.examples --warnings-as-errors
mix compile --warnings-as-errors
mix format --check-formatted
git diff --check
```

Run from `/Users/mhostetler/Source/Jido/spikes/jarvis`:

```sh
mix test test/jarvis/control_test.exs test/jarvis/plugins_test.exs test/jarvis/assessment_schedule_test.exs
mix compile --warnings-as-errors
mix format --check-formatted
mix test
git diff --check
```

Removal checks from the Jarvis repository:

```sh
rg -n "Jarvis\.Plugins\.VSM|Jarvis\.Actions\.VSM|Plugins\.VSM\.Record" lib test README.md
rg -n "Jido\.Plugin\.Bus\.DSL|bus\(:control\)|signal_bus" lib test README.md
```

Requirement traceability:

| Requirement | Units | Verification |
| --- | --- | --- |
| R1 | U3-U6 | Runtime and Chat tool integration tests |
| R2 | U4-U6 | Timer state and lifecycle tests |
| R3 | U2, U4-U6 | Memory Plugin, SQLite, and Memories UI regression tests |
| R4 | U1-U6 | Cell definition, resident Agent, and lifecycle tests |
| R5 | U1-U2, U5-U6 | Package dependency and source-boundary checks |
| R6 | U2-U3, U6 | Control flow and false-claim tests |
| R7 | U2, U4-U6 | S4 evidence and no-authority tests |
| R8 | U2-U4, U6 | Blocked-S1 responsiveness and failure-isolation tests |
| R9 | U2-U3, U6 | Ecto run, trace, lease, retry, and terminal-state checks |
| R10 | U3-U6 | LiveView and role-source tests |
| R11 | U3-U6 | Removal searches and compiled definition tests |
| R12 | U1-U6 | No-custom-runtime structure checks |
| R13 | U1, U6 | Standard Cell and example regression suites |
| R14 | U1-U6 | Final repository gates |

### Rollout and Recovery

This is a local spike with no deployment. Use an expand, migrate, and remove
sequence:

1. Add the package contract and keep current standard Cells valid.
2. Add the Jarvis Cell without live callers.
3. Move control while the old public projection remains active.
4. Move intelligence and install Status as the only public projection.
5. Remove the inactive old Plugin and Bus after both paths pass.

The Ecto schema and stored meanings stay unchanged. If U3 or U4 fails, keep the
old owner for that Signal family and remove only the incomplete new routing.
Do not run both owners for one live Signal type. After U5 deletes the old path,
recovery is forward repair through the owning unit, not an automatic runtime
fallback.

### Risks and Assumptions

- **Risk:** The completed `jido_vsm` roadmap is still uncommitted. New Cell
  changes can hide or damage that work. U1 must start from a recoverable
  checkpoint or a separate worktree.
- **Risk:** A broad Cell customization API can recreate the removed V2 profile
  system. Keep the new contract literal, static, and limited to Jido topology
  data.
- **Risk:** Root and Cell output forwarding can create a Signal loop. Compile
  and runtime tests must prove that each port has one direction.
- **Risk:** A repeated lease acquire by the same run can currently look like a
  competing run. U2 must make same-run acquisition idempotent before live
  migration.
- **Risk:** Ecto or file effects can complete before an Agent turn commits.
  The current file write is repeatable, but the design does not generalize this
  to non-idempotent capabilities.
- **Risk:** Main-Agent status becomes an event projection and can lag S4 by one
  turn. Tests and UI text must not claim synchronous Cell-wide snapshots.
- **Risk:** ETS Jido persistence does not survive a VM restart. Durable Ecto
  control records do not imply durable role inboxes or atomic Cell recovery.
- **Assumption:** The local Jido V3 topology keeps nested Agent ownership and
  member restart behavior used by the current `jido_vsm` examples.
- **Assumption:** No supported external consumer uses the Jarvis local Bus.
  U5 must confirm this with repository search before removal.
- **Assumption:** `Jarvis.Runtime.status/0` is a local public boundary, and its
  current top-level `:schedule` and `:vsm` keys should remain stable through
  this migration.

### Open Planning Decisions

None. Dynamic cells, model-based VSM decisions, Memory extraction, durable
outbox delivery, and VM-restart recovery are explicit later decisions.

### Definition of Done

- `jido_vsm` supports the standard Cell and one static application Cell form.
- The application Cell accepts one S1 operation and application-owned role
  Agent modules without a custom runtime.
- The main Jarvis Agent owns Timer, local Memory, Status, and one nested VSM
  Cell.
- S5 policy runs before S1 work. S3* verifies actual results independently.
- S4 owns assessment and observation work but cannot authorize S1 work.
- A blocked S1 turn does not block the main Agent or S4.
- Ecto run, trace, and lease records keep their current meaning and UI use.
- `Jarvis.Runtime` and Chat tools keep their caller-visible behavior.
- Memory remains local and Timer remains in Jido core.
- The local VSM Plugin, control Action, old transition-counter owner, and
  loopback Bus are absent from active Jarvis source. Status keeps the compatible
  `:transitions` value.
- Both repository verification suites pass on the final unchanged source.
- Documentation states the ETS, side-effect, and non-atomic Cell limits.
- No commit, push, release, or remote change is part of this plan.

### Planning Sources

- [Jarvis Agent definition](../../lib/jarvis/agent.ex)
- [Jarvis Runtime](../../lib/jarvis/runtime.ex)
- [Jarvis VSM Plugin](../../lib/jarvis/plugins/vsm.ex)
- [Jarvis control entry point](../../lib/jarvis/control.ex)
- [Jarvis control workflow](../../lib/jarvis/control/workflow.ex)
- [Jarvis control tests](../../test/jarvis/control_test.exs)
- [Jarvis Plugin integration tests](../../test/jarvis/plugins_test.exs)
- [Timer consolidation plan](2026-11-14-0656-stateful-timer-plan.md)
- [Local Memory plan](2026-11-14-0702-thin-store-backed-memory-plugin-plan.md)
- [Jido VSM README](../../../../jido_workflow/jido_vsm/README.md)
- [Jido VSM Cell source](../../../../jido_workflow/jido_vsm/lib/jido_vsm/cell.ex)
- [Jido VSM CellGroup source](../../../../jido_workflow/jido_vsm/lib/jido_vsm/cell_group.ex)
- [Jido VSM DynamicCell source](../../../../jido_workflow/jido_vsm/lib/jido_vsm/dynamic_cell.ex)
- [Jido VSM standard role Agents](../../../../jido_workflow/jido_vsm/lib/jido_vsm/agent/s1.ex)
- [Jido VSM standard adapter](../../../../jido_workflow/jido_vsm/lib/jido_vsm/adapter/default.ex)
- [Jido VSM package tests](../../../../jido_workflow/jido_vsm/test/jido_vsm/cell_test.exs)
- [Jido VSM architecture guide](../../../../jido_workflow/jido_vsm/docs/v3-architecture.md)
- [Jido VSM current roadmap plan](../../../../jido_workflow/jido_vsm/docs/plans/2026-11-14-0810-example-roadmap-plan.md)
- [Jido nested topology example](../../../../jido_core/jido/examples/10_declared_agent_topologies/10_04_nested_agents/hierarchy.ex)

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-14-0814-jarvis-jido-vsm-adoption-plan.md`
- HTML: not requested
- Beadwork: not requested
