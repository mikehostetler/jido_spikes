---
title: Consolidate periodic scheduling in Jido Timer
type: implementation-plan
date: 2026-11-14
last_reviewed: 2026-11-14
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Consolidate periodic scheduling in Jido Timer

## Goal Capsule

- Objective: `Jido.Plugin.Timer` is the one public timer owner for delayed,
  static periodic, dynamic interval, and cron Signals. Jarvis uses it without a
  continual-loop or Cycle Plugin.
- Means: Rename the Scheduler public API to Timer, add stateful interval
  lifecycle, move useful Heartbeat behavior into a static Timer interval,
  remove Heartbeat, and migrate Jarvis to Timer Directives.
- Authority: Local writes in the Jido core and Jarvis repositories. Do not commit, push, publish, or change another repository.
- Stop conditions: Stop if saved cron state cannot remain valid, if the legacy delivery-adapter callback must change without a compatibility path, or if interval scheduling requires Timer to own Agent work or work acknowledgement.
- Next executor: An Elixir implementer working in Jido core first and Jarvis second.

## Product Contract

### Summary

Replace the Scheduler public name with Timer and extend it with stateful
interval schedules and recurring-schedule pause and resume. Move static
periodic Signal production from Heartbeat into Timer. Keep Heartbeat only as a
migration reference that directs users to Timer. Remove the two loop Plugin
implementations from Jarvis. Prove Timer with core contract tests and the main
Jarvis Agent.

### Problem Frame

The core Scheduler already owns recurring cron definitions, timer
reconciliation, generations, occurrence metadata, and restart recovery. Its
static authoring DSL also has an `every` timing form. Its live API cannot create
a recurring interval definition or keep a recurring definition while paused.

The separate Heartbeat Plugin owns another fixed-delay timer. This duplicates
timer runtime, validation, restart, and documentation rules. Timer needs one
static declaration mode so periodic input does not need a second engine.

Jarvis currently fills that gap with `Jarvis.Plugins.ContinualLoop` and `Jido.Plugin.Cycle`. The Cycle Plugin chains runtime-only one-shot timers and duplicates schedule lifecycle state. It also loses its next wake-up after Timer or AgentServer replacement.

### Actors

- A Jido Agent author creates and controls recurring interval or cron schedules.
- The Timer runtime produces future Signals from committed schedule state.
- A delivery adapter can persist cron schedules outside AgentServer. External interval delivery is not in this change.
- Jarvis maps its application control Signals to Timer Directives and handles assessment Signals as normal Agent work.

### Requirements

- **R1:** Timer exposes a validated `every` Directive for one positive millisecond interval and one Signal template.
- **R2:** Timer exposes idempotent pause and resume Directives for interval job IDs, and cancel for either recurring kind. Pause keeps the interval definition. Resume creates a new logical generation.
- **R3:** Timer keeps cron definitions and interval definitions in portable Agent state. Each interval has a running or paused status. Existing `%{cron: ...}` saved state remains valid.
- **R4:** The local runtime reconciles active interval timers, rejects stale timer tokens and state versions, restores active timers after replacement, and does not replay intervals that passed while offline.
- **R5:** Interval occurrences use the existing occurrence metadata contract. Timer owns timer production only. It does not own Agent work, completion, retry, acknowledgement, or durable business delivery.
- **R6:** Existing one-shot, cron, static DSL, and delivery-adapter behavior remains valid. Timer rejects an active interval when an external delivery adapter is configured.
- **R7:** Jarvis contains no continual-loop or Cycle Plugin module, file, state key, route, or test support. It declares only the core Timer for this capability.
- **R8:** `Jarvis.Runtime.prompt/2`, `pause/0`, `resume/0`, and `status/0` still control one standing assessment schedule. Status reports a `:schedule` projection with the purpose and lifecycle state.
- **R9:** Core and Jarvis tests prove interval delivery, pause, stale occurrence rejection, resume, replacement, cancellation, runtime recovery, and the Jarvis VSM assessment flow without a model call.
- **R10:** The public Plugin, Directive, runtime, test, Covenant, guide, and
  Jarvis namespace is `Jido.Plugin.Timer`. No active
  `Jido.Plugin.Scheduler` API remains.
- **R11:** Static Timer Agent options create one running interval with the
  standard periodic Signal defaults. `Jido.Plugin.Heartbeat` is removed. All
  periodic Signal users migrate to Timer.

### Key Flows

1. An Action returns `Timer.every(job_id, interval_ms, signal)`.
2. Timer commits the interval definition as active Agent state.
3. The runtime starts one fixed-delay timer after the commit.
4. A current timer produces a fresh Signal and arms the next timer.
5. Pause keeps the definition but removes it from the runtime's active desired set.
6. Resume increments a tagged definition generation and starts a full new interval.
7. Runtime replacement reads committed state and restores only active future timers.
8. Jarvis emits one immediate assessment when it starts or resumes, then Timer produces later assessment Signals.

### Acceptance Examples

- A minimal Agent receives at least two interval Signals from one `every` definition.
- Pause cancels the current interval timer but leaves the definition in Agent state.
- Resume creates a new generation and does not accept an occurrence from the prior generation.
- Timer or AgentServer replacement restores an active interval and keeps a paused interval paused.
- An existing cron-only delivery adapter continues to receive its current cron definition map.
- An active interval with an external delivery adapter returns a structured unsupported-delivery error.
- A static Timer declaration starts periodic Signals through the normal Timer
  interval runtime.
- A bare Timer declaration does not start an implicit interval.
- The removed Heartbeat modules cannot load and Catalog does not include them.
- Jarvis starts with a purpose, records repeated VSM assessments, pauses, resumes, and reports the same purpose without either loop Plugin.

### Success Criteria

- Focused core Timer tests pass for API, state, local runtime, recovery, codec, and adapter compatibility.
- Core authoring, Covenant, architecture, format, and repository gates pass.
- Focused Jarvis Timer and Plugin tests pass.
- Jarvis compile, format, and full test gates pass.
- A source search finds no active continual-loop or Cycle implementation in Jarvis.

### Scope Boundaries

In scope:

- Core Timer `Every`, `Pause`, and `Resume` Directives and constructors.
- Public Scheduler-to-Timer namespace rename across source, tests, Covenant,
  guides, architecture records, examples, and Jarvis.
- Static Timer interval options and the default Timer Tick Signal.
- Removal of the Heartbeat Plugin, runtime, compatibility Signal, tests, and
  Covenant component.
- Additive Timer state for interval definitions with local lifecycle status.
- Local interval timer reconciliation and recovery.
- No change to the delivery-adapter contract; external interval delivery remains unsupported.
- Timer Covenant, API documentation, ADR, architecture map, and tests.
- Jarvis application control Actions, status projection, tests, and documentation.
- Removal of the Jarvis continual-loop and Cycle source and test files.

Out of scope:

- Completion-driven recurrence or waiting for Agent work.
- Pending work, work retries, admission, acknowledgement, or delivery replay.
- Missed-interval replay after downtime.
- Durable delivery implementation in Jarvis.
- A turn counter owned by Timer.
- Changes to Jidoka or another downstream repository.
- Commit, push, pull request, release, or publication.

### Key Decisions

- Timer is the only Plugin owner of recurring timer lifecycle.
- Timer is the only bundled owner of fixed-delay timer production. Heartbeat
  is a deprecated facade, not a capability engine.
- Interval schedules use fixed delay. The next timer starts after the prior occurrence is produced.
- The first interval and a resumed interval wait one full interval. An application can emit an immediate Signal in the same control Turn.
- Pause and resume apply only to interval definitions.
- Timer state expands additively. It does not replace the current `:cron` map.
- Delivery adapters keep the current callback and cron data shape. An active interval is rejected when an adapter is configured.
- Jarvis purpose stays in the scheduled Signal data. Jarvis derives status from Timer state.

### Rejected Alternatives

- Keep Cycle as a second Plugin: this duplicates timer lifecycle state and still depends on Timer.
- Keep Heartbeat as a second runtime: this duplicates the same fixed-delay
  timer lifecycle under a different name.
- Replace Timer cron state with one new map: this breaks saved state and current adapter inputs.
- Make Timer wait for assessment completion: this crosses the accepted boundary between timer production and Agent work.
- Make every interval fire immediately: this makes `every` unlike a schedule and complicates restart behavior. Jarvis can emit its own immediate assessment.
- Change `DeliveryAdapter.reconcile/2` in place: Jidoka currently implements the cron-specific callback.

### Dependencies

- Jido core Timer source, Covenant component, SchedEx cron runtime, and Plugin Directive lifecycle.
- Jarvis path dependency at `../../jido_core/jido`.
- Existing Jarvis VSM and memory Plugins.
- Existing core and Jarvis baseline tests: 34 focused core tests and 13 focused Jarvis tests passed before implementation on 2026-11-14.

### Outstanding Questions

None block implementation. Ordinary module names and helper layout remain executor choices within the contracts below.

### Sources

- [Core Timer](../../../../jido_core/jido/lib/jido/plugin/timer.ex)
- [Timer runtime](../../../../jido_core/jido/lib/jido/plugin/timer/runtime.ex)
- [Timer delivery adapter](../../../../jido_core/jido/lib/jido/plugin/timer/delivery_adapter.ex)
- [Timer Covenant](../../../../jido_core/jido/test/contracts/jido.plugin/timer.obligations.md)
- [Timer static DSL](../../../../jido_core/jido/lib/jido/plugin/timer/dsl.ex)
- [Jarvis Agent](../../lib/jarvis/agent.ex)
- [Jarvis assessment schedule](../../lib/jarvis/assessment_schedule.ex)

## Planning Contract

### Product Contract Preservation

Product Contract unchanged. The plan selects technical compatibility and
lifecycle rules that implement R1-R11 without giving Timer ownership of Agent
work.

### Baseline System

`Jido.Plugin.Scheduler` owns `%{cron: %{job_id => spec}}` and runtime cron
jobs. `schedule/2` creates one runtime-only delayed Signal. `cron/4` creates or
replaces a recoverable recurring definition. `cancel/1` removes a cron
definition. The runtime reconciles the full cron map after a state commit and
can delegate it to `DeliveryAdapter.reconcile/2`.

`Jido.Plugin.Scheduler.DSL` already normalizes `every` and `cron` timing, but
it is an authoring-only provider and starts no timer.

At baseline, `Jido.Plugin.Heartbeat` owns a second fixed-delay runtime and the
default heartbeat Signal. The target removes it and moves users to
`Jido.Plugin.Timer`.

Jarvis declares `Jido.Plugin.Cycle` and Timer. Cycle owns purpose payload, status, generation, sequence, turn count, and interval. It schedules its own internal tick through Timer one-shots. The old `Jarvis.Plugins.ContinualLoop` and `Jarvis.Actions.Loop` source also remains in the spike.

### Target System

The core flow is:

```text
Agent Action
-> Every, Cron, Pause, Resume, or Cancel Directive
-> Timer reducer commits portable recurring state
-> Timer runtime reconciles active definitions
-> current interval or cron occurrence produces one fresh Signal
-> Agent route performs application work
```

The Jarvis flow is:

```text
Runtime control Signal
-> Jarvis schedule-control Action
-> Timer Directive plus optional immediate assessment
-> Timer commits and owns later timers
-> jarvis.vsm.assess route records one finite assessment
```

### Key Technical Decisions

#### KTD1: Keep one lifecycle field in each interval definition

- **Decision:** Keep `:cron`. Add `:every` for interval specs. Each interval spec has `status: :running | :paused`. Creating either recurring kind replaces the same job ID in the other kind. Cancel removes the definition.
- **Reason:** R3 and R6 require saved cron state and existing cron callers to remain valid.
- **Rejected alternative:** Replace `:cron` with a normalized `:recurring` map.
- **Consequences:** Runtime code filters paused intervals from the active interval set. State validation rejects cross-kind duplicate IDs and invalid interval status.
- **Governs:** R1-R4, R6, U1, and U2.

#### KTD2: Give interval schedules logical generations

- **Decision:** A new interval starts at generation `0` unless the caller supplies a generation. Replacing an interval without an explicit generation advances the stored generation. Resume advances an interval generation. Generation overflow returns a validation error.
- **Reason:** R2, R4, and R9 require an application to reject an occurrence already delivered under an older activation.
- **Rejected alternative:** Use only runtime timer tokens. A token cannot retract a Signal already sent to AgentServer.
- **Consequences:** Plain cron schedules remain untagged. Interval schedules are tagged by default. Applications that need an immediate Signal create it separately from the recurring occurrence.
- **Governs:** R2, R4, R5, R9, U1-U3.

#### KTD3: Use fixed-delay interval reconciliation

- **Decision:** Track one timer, token, scheduled UTC instant, and spec per active interval job. A current tick produces its Signal and then arms the next timer. Pause, cancel, replacement, adapter use, and runtime termination cancel the timer.
- **Reason:** This matches the requested continual behavior without work acknowledgement or missed-slot replay.
- **Rejected alternative:** Use a fixed-rate timer that can place several messages in the mailbox while the runtime is delayed.
- **Consequences:** Delivery can drift. Restart and resume start a full interval from the new runtime state. `time_scale` remains a cron clock option.
- **Governs:** R4, R5, U2.

#### KTD4: Keep the adapter contract unchanged

- **Decision:** Keep `DeliveryAdapter.reconcile/2` for the current cron map. Return a structured reconciliation error when an active interval is used with an external adapter.
- **Reason:** R6 requires current Jidoka cron delivery to remain valid without hiding unsupported interval behavior.
- **Rejected alternative:** Send a new value to the old callback.
- **Consequences:** This change does not expand a durable delivery contract. External interval support needs a separate design.
- **Governs:** R4-R6, U2.

#### KTD5: Keep Jarvis control application-specific

- **Decision:** Add Jarvis routes and one application Action for start, pause, and resume. The Action returns Timer Directives and emits an immediate assessment on start or resume. `AssessPurpose` reads `%{purpose: purpose}` and rejects a tagged occurrence whose generation is not current or whose schedule is paused.
- **Reason:** R7 and R8 remove the generic loop Plugins while keeping Jarvis caller behavior.
- **Rejected alternative:** Add generic control Signal routes to Timer. Timer currently exposes Directives and does not own application command naming.
- **Consequences:** Jarvis status changes from `:cycle` to `:schedule`. VSM assessment count is the observable run count.
- **Governs:** R7-R9, U3.

#### KTD6: Use one Timer namespace and runtime

- **Decision:** Rename the Scheduler public namespace and owned state key to
  Timer. Let static Timer Agent options create one normal `every` definition.
  Remove Heartbeat and its runtime.
- **Reason:** R10 and R11 require one clear public owner and one fixed-delay
  engine.
- **Rejected alternative:** Keep Scheduler or Heartbeat as a second runtime or
  public alias.
- **Consequences:** Callers migrate to Timer. No Heartbeat compatibility module
  remains.
- **Governs:** R10-R11 and U1-U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| Public Plugin name | `Jido.Plugin.Scheduler` | `Jido.Plugin.Timer` | Intentional beta rename; active callers migrate |
| Timer public API | `schedule`, `cron`, `cancel` | Add `every`, `pause`, and `resume` | Additive API |
| Timer Agent state | `:cron` map | Add a defaulted `:every` map with status in each interval | Old cron-only state must parse |
| Timer runtime | one-shots and SchedEx cron jobs | Add fixed-delay interval timers and shared lifecycle reconciliation | Token and cleanup races need direct tests |
| Occurrence metadata | optional cron generation and UTC slot | Reuse for interval generation and due time | No Signal data change |
| Delivery adapter | required cron `reconcile/2` | No callback change; reject active intervals | Cron path stays valid |
| Timer Covenant | cron-specific public boundary text | Add interval and lifecycle obligations | Must keep work delivery excluded |
| Heartbeat | Separate fixed-delay runtime | Remove it; use a static Timer interval | Intentional beta removal; callers migrate |
| Jarvis Agent | Cycle plus Timer | Timer only, with application routes | State and status shape changes |
| Jarvis assessment | Cycle envelope | Scheduled Signal data plus occurrence context | Stale generation check moves to application Action |
| Jarvis source and tests | Two loop implementations | Remove both and add Timer proof | Source search is a final gate |

### Implementation Units

#### U1: Consolidate the Timer public API and state

- **Outcome:** Timer can validate and commit interval, pause, resume, and cancel Directives while old cron-only state remains valid.
- **Requirements:** R1-R3, R5, R6, R10, R11.
- **Dependencies:** None.
- **Affected surfaces:** Rename the Scheduler source, tests, Covenant, guides,
  and examples to Timer; add Directives under `lib/jido/plugin/timer/`; update
  Heartbeat references to Timer migration guidance; update ADR and architecture
  documents.
- **Implementation direction:** Add a defaulted `:every` state field. Validate
  portable job IDs, positive bounded intervals, portable Signals, reserved
  occurrence metadata, cross-kind uniqueness, and interval status. Let static
  Agent options create one normal interval. Remove Heartbeat source, tests,
  Catalog entry, and Covenant component. Keep Directive list order. Advance
  interval generation on resume and implicit replacement.
- **Test scenarios:** Constructor bounds; option errors; state defaults; static
  Timer auto-start; bare Timer; no Heartbeat module or Catalog entry; old saved
  state; same-ID kind replacement; Directive order; unknown pause and resume
  idempotence; cancel cleanup; generation advance and overflow; public API
  inventory.
- **Verification:** Run focused Timer API, contract, and codec tests.
- **Completion signal:** Public and persisted state contracts pass without runtime interval behavior.

#### U2: Reconcile interval timers and adapter delivery

- **Outcome:** Active interval definitions produce and recover future Signals; paused, changed, removed, and stale interval work stays inert; adapter compatibility is explicit.
- **Requirements:** R2-R6, R9.
- **Dependencies:** U1 supplies validated state and Directives.
- **Affected surfaces:** Timer runtime and delivery-adapter behavior; runtime contract tests; Timer module documentation and Covenant runtime obligations.
- **Implementation direction:** Keep one tracked fixed-delay timer per active interval. Store the due UTC instant with the token. On a current tick, deliver a fresh tagged Signal and arm the next interval. Reconcile active sets after each recurring Directive. Preserve the adapter callback for cron-only desired state and reject active external intervals.
- **Test scenarios:** Two interval ticks; fresh IDs; stable occurrence identity for a repeated coordinate; pause; resume generation; replacement; cancel; stale state version; stale token; termination; runtime replacement; Agent restore; adapter with cron; adapter rejection with interval; retry recovery.
- **Verification:** Run focused runtime and recovery tests, then Timer contract and authoring gates.
- **Completion signal:** All core Timer gates pass and the runtime owns no Agent work state.

#### U3: Replace Jarvis loop Plugins with Timer

- **Outcome:** Jarvis uses only core Timer for standing assessment timing, and all loop Plugin source and tests are removed.
- **Requirements:** R7-R9.
- **Dependencies:** U2 supplies the complete Timer behavior.
- **Affected surfaces:** `Jarvis.Agent`, `Jarvis.Runtime`, a new application schedule-control Action, `AssessPurpose`, Chat tool text, main Agent tests, README, and active plans. Delete `lib/jido/plugin/cycle*`, `lib/jarvis/plugins/continual_loop.ex`, `lib/jarvis/actions/loop.ex`, and Cycle test support.
- **Implementation direction:** Use one stable job ID. Store purpose in the interval Signal template. Derive `:schedule` status from Timer state. Emit one immediate assessment on start and resume. Compare tagged occurrence generation with the current definition before VSM mutation. Prove the lifecycle through the main Jarvis Agent.
- **Test scenarios:** Start and two assessments; pause; stale prior-generation occurrence; resume; purpose replacement; cancel or teardown; status projection; memory and information Signals do not change schedule state; Plugin provider list; no loop source references.
- **Verification:** Run focused Jarvis Timer and Plugin tests, source search, then compile, format, and full tests.
- **Completion signal:** Jarvis has no Cycle or continual-loop implementation and all Jarvis gates pass against the local core dependency.

### Work Graph

- Initial frontier: U1.
- Critical path: U1 -> U2 -> U3.
- Parallel groups: None. Runtime code depends on the state contract, and Jarvis depends on the final runtime behavior.
- Final integration unit: U3.

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Core state and API | U1 | Focused Timer API, contract, and codec tests | New Directives and old state pass |
| Core runtime | U2 | Focused runtime and recovery tests | Interval lifecycle and recovery pass |
| Core contracts | U1-U2 | Covenant, authoring, architecture, quality, and full tests | No contract or regression failure |
| Jarvis Timer proof | U3 | Main Agent Timer state and Plugin tests | Start, pause, stale reject, resume, and state projection pass |
| Jarvis integration | U3 | Plugin and control tests | VSM assessments and status pass |
| Removal | U3 | Source and file search | No active Cycle or continual-loop implementation remains |
| Jarvis repository | U3 | Compile, format, and full tests | No warning, format, or test failure |

Run from `/Users/mhostetler/Source/Jido/jido_core/jido`:

```sh
mix test test/jido/plugin/timer test/jido/agent/timer_codec_test.exs
mix test.authoring
mix test.contracts
mix reach.check --arch --smells
mix format --check-formatted
mix test
mix quality
mix test.ci
```

Run from `/Users/mhostetler/Source/Jido/spikes/jarvis`:

```sh
mix test test/jarvis/plugins_test.exs test/jarvis/assessment_schedule_test.exs test/jarvis/control_test.exs
rg -n "Jido.Plugin.Cycle|ContinualLoop|continual_loop|jarvis.loop" lib test README.md
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

Requirement traceability:

| Requirement | Units | Verification |
| --- | --- | --- |
| R1-R3, R10-R11 | U1 | Core state, namespace, static interval, and API gate |
| R4-R6 | U1, U2 | Runtime, adapter, authoring, and contract gates |
| R7-R8 | U3 | Removal and Jarvis integration gates |
| R9 | U2, U3 | Core recovery and both Jarvis setup tests |

### Rollout and Recovery

This is a local beta SDK change and a local spike migration. The state change is additive. Old cron-only checkpoints remain valid. Delivery adapters continue on their current cron-only callback. If an interval is used with an external adapter, activation or reconciliation fails with a structured error instead of dropping the interval.

Jarvis changes only after core gates pass. If Jarvis integration fails, repair the Jarvis application Action or status projection. Do not restore a second timer-owning Plugin as a fallback.

### Risks and Assumptions

- **Risk:** A Signal can already be in the AgentServer mailbox when pause commits. Runtime tokens cannot retract it. Generation metadata plus the Jarvis current-generation check detects this case.
- **Risk:** Local intervals and external cron delivery use different paths. Contract tests cover each path and reject their unsupported combination.
- **Risk:** Fixed-delay drift is expected. No cadence or throughput promise is in scope.
- **Risk:** A broad core gate can expose an unrelated existing failure. Record it separately and keep focused evidence for the changed component.
- **Assumption:** Nested Joi defaults make old `%{cron: ...}` values expand safely. U1 must prove this before runtime work continues.
- **Assumption:** AgentServer serializes state commits for one Agent. Timer still fences stale state versions and timer tokens.

### Open Planning Decisions

None. The work can start at U1 without a product, public-contract, data, or operating-policy decision.

### Definition of Done

- R1-R11 have implementation and current test evidence.
- U1-U3 reach their completion signals.
- Old cron constructors, saved state, local behavior, and legacy adapter callback remain valid.
- Active interval schedules recover; paused schedules stay paused; missed intervals are not replayed.
- Timer owns timer lifecycle and no application work state.
- Heartbeat has no runtime or timer engine.
- Jarvis uses Timer only and reports `:schedule` status.
- The removed Cycle and continual-loop files and active references are absent.
- Required core and Jarvis verification gates pass, or any broader unrelated limit is named with focused passing evidence.
- No commit, push, publication, or remote change occurs.

### Planning Sources

- Current Jido core Timer source, tests, Covenant records, ADR conventions, and architecture map.
- Current Jarvis Agent, Runtime, Cycle, continual-loop, VSM assessment, Chat tools, and tests.
- Jidoka's current `Jido.Plugin.Timer.DeliveryAdapter` implementation, inspected only to preserve the legacy cron callback.
- Baseline checks on 2026-11-14: 34 focused core tests passed; 13 focused Jarvis tests passed.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-14-0656-stateful-timer-plan.md`
- HTML: not requested
- Beadwork: not requested
