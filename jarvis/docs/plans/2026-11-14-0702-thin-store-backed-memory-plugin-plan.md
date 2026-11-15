---
title: Thin store-backed Jarvis memory plugin
type: implementation-plan
date: 2026-11-14
last_reviewed: 2026-11-14
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Thin store-backed Jarvis memory plugin

## Goal Capsule

- Objective: Test a thin Jido memory Plugin in Jarvis while SQLite remains the only memory store.
- Means: Configure `Jarvis.Plugins.Memory` with a local store module and namespace, pass that configuration through Jido Plugin input, and remove Agent-owned memory state and counters.
- Authority: Local implementation and tests only when separately authorized. No commit, push, package extraction, or Jido SDK change.
- Stop conditions: Stop if the change needs a new dependency, a database migration, an embedding system, or a change to the Jido Plugin contract.
- Next executor: An Elixir engineer working in the Jarvis spike.

## Product Contract

### Summary

Jarvis needs a small local proof that one Jido Plugin can provide explicit memory recall and storage through a configured store. The existing SQLite FTS5 context remains the source of truth. The proof must stay local to Jarvis and must not become a general package yet.

### Problem Frame

The current Plugin mixes two state systems. SQLite owns durable memory records, while the Agent owns a namespace and usage counters. Actions write SQLite before returning directives that update the Agent counters. This split adds state that does not control memory behavior and can disagree with the store.

### Actors

- `Jarvis.Agent`, which recalls and stores memory through Jido Signal routes.
- `Jarvis.Actions.AssessPurpose`, which recalls memory for the standing purpose.
- Jarvis developers, who use this spike to test the Plugin boundary before any extraction.

### Requirements

- **R1:** SQLite through `Jarvis.Memories` is the only source of truth for stored memory.
- **R2:** `Jarvis.Plugins.Memory` owns no Agent state, counters, directives, or runtime process.
- **R3:** The Plugin accepts a configured store module and namespace and makes them available to its Actions through Jido Plugin input.
- **R4:** `jarvis.memory.recall` and `jarvis.memory.remember` keep their current request and reply behavior.
- **R5:** Purpose assessment uses the same configured store and continues to record recalled memory IDs.
- **R6:** Existing direct SQLite users, including chat preparation and the `/memories` LiveView, keep their current behavior.
- **R7:** The implementation remains local to Jarvis and adds no dependency, migration, embedding work, vector search, asynchronous queue, or package extraction.

### Key Flows

Recall:

```text
Signal -> Plugin preparation -> configured store and namespace -> Memory Action
       -> Jarvis.Memories.recall/3 -> structured reply
```

Remember:

```text
Signal -> Plugin preparation -> configured store and namespace -> Memory Action
       -> Jarvis.Memories.remember/1 -> stored row ID reply
```

Purpose assessment:

```text
scheduled assessment -> Plugin preparation -> configured store recall
                 -> memory IDs in VSM assessment
```

### Acceptance Examples

1. Given the main Agent Plugin configuration names `Jarvis.Memories` and namespace `"jarvis"`, a remember Signal stores one SQLite record in that namespace and returns its ID.
2. Given a matching active record, a recall Signal returns the record with the same current result shape and FTS5 ordering.
3. Given a purpose assessment, the assessment records matching memory IDs without reading or changing an Agent `:memory` field.
4. Given an information Signal, the memory store remains unchanged.
5. Given a test store in Action context, the Action uses that store instead of calling `Jarvis.Memories` directly.
6. Given the final Agent snapshot, no `:memory` key or memory usage counter exists.

### Success Criteria

- Focused memory, Plugin, and LiveView tests pass.
- The complete test suite and repository checks pass.
- The main Agent still recalls and stores FTS5 memory through the existing Signal routes.
- No memory data, counter, or namespace is duplicated in Agent state.

### Scope Boundaries

In scope:

- A small local store behavior.
- Plugin option validation and prepared configuration.
- Recall and remember route integration.
- Purpose assessment and status migration away from Agent memory state.
- Focused tests and current documentation.

Out of scope:

- Embeddings, vector search, hybrid search, or model calls.
- Forget and supersede Signal routes. The existing direct context and UI operations remain.
- Operation IDs, durable outboxes, retries, or asynchronous completion Signals.
- A new Plugin runtime process.
- Extraction to Jido core or another package.
- Database schema or FTS5 query changes.
- Repair of stale supersession behavior.
- Automatic memory creation from chat.

### Key Decisions

- Keep the module named `Jarvis.Plugins.Memory` and keep all new contracts in this repository.
- Use `Jarvis.Memories` directly as the configured store. Do not add an adapter wrapper with no current behavior.
- Keep recall and remember synchronous because this is a local proof and SQLite is local.
- Remove usage counters instead of replacing them. Add Telemetry only after a real observation need exists.

### Rejected Alternatives

- A reusable `Jido.Plugin.Memory` package is premature before the local contract is tested.
- Agent-owned memory records or counters duplicate the store and create consistency work.
- A supervised Plugin runtime and post-commit directives add asynchronous behavior that this proof does not need.
- Automatic prompt injection couples storage to one AI use case. Chat prompt assembly stays application-owned.

### Dependencies

- Existing local Jido path dependency.
- Existing Ecto SQLite repository and FTS5 tables.
- Existing `Jarvis.Memories` recall and mutation functions.

No new dependency is required.

### Outstanding Questions

None blocking. The local proof intentionally accepts the current synchronous SQLite effect boundary. A later extraction must decide whether mutation completion needs post-commit or durable delivery semantics.

### Sources

- [Jarvis README](../../README.md)
- [Current memory Plugin](../../lib/jarvis/plugins/memory.ex)
- [Current memory Action](../../lib/jarvis/actions/memory.ex)
- [SQLite memory context](../../lib/jarvis/memories.ex)

## Planning Contract

### Product Contract Preservation

Product Contract unchanged. This plan uses the user-selected thin, store-backed, Jarvis-local direction and excludes embeddings.

### Current System

`Jarvis.Agent` loads `Jarvis.Plugins.Memory` without options. The Plugin owns `state.memory`, including namespace, recall count, and write count. `Jarvis.Actions.Memory` reads that state, calls `Jarvis.Memories`, and returns a `Memory.Record` directive to update a counter. `Jarvis.Actions.AssessPurpose` follows the same pattern for recall. `Jarvis.Runtime.status/0` exposes the memory state.

The durable records already live in SQLite. `Jarvis.Memories.recall/3` applies namespace and lifecycle filters and uses FTS5 `bm25` ordering. Chat preparation and the memory LiveView call the context directly and do not use the main Agent Plugin.

### Target System

`Jarvis.Agent` configures `Jarvis.Plugins.Memory` with `store: Jarvis.Memories` and `namespace: "jarvis"`. The Plugin validates this configuration in `prepare/2` and returns it as portable prepared Plugin input. Memory Actions and purpose assessment read the prepared configuration from their Action context and call the configured store.

The Plugin has no `state_spec/1`, directives, reducer, dispatcher, or child process. `Jarvis.Runtime.status/0` returns only schedule and VSM state. SQLite data, FTS5 behavior, chat recall, and the memory LiveView remain unchanged.

### Key Technical Decisions

#### KTD1 — Keep a Jarvis-local Plugin contract

- **Decision:** Keep `Jarvis.Plugins.Memory` and add a local `Jarvis.Memory.Store` behavior.
- **Reason:** R7 requires a local test before extraction.
- **Rejected alternative:** Add `Jido.Plugin.Memory` under the spike or change Jido core. Either name would imply a stable general contract before this proof exists.
- **Consequences:** A later extraction can rename and widen the contract after evidence exists. No cross-package work is required now.
- **Governs:** R3, R7, U1.

#### KTD2 — Use prepared Plugin input for configuration

- **Decision:** Use the prepared-input pattern in `Jarvis.Plugins.Memory`: validate options in `prepare/2`, then read `%Jido.Plugin.Input{prepared: config}` from Action context.
- **Reason:** Store module and namespace are configuration, not mutable Agent state. Jido already provides a portable prepared input boundary.
- **Rejected alternative:** Read application configuration or hard-code `Jarvis.Memories` inside each Action. That would not test Plugin configuration or store substitution.
- **Consequences:** Configuration errors reject the turn before a memory call. The store module must export `recall/3` and `remember/1`.
- **Governs:** R2, R3, R4, R5, U1.

#### KTD3 — Make `Jarvis.Memories` the store implementation

- **Decision:** Add `@behaviour Jarvis.Memory.Store` to `Jarvis.Memories`; do not add a pass-through SQLite adapter.
- **Reason:** The existing context already owns the required store operations and FTS5 behavior.
- **Rejected alternative:** Add `Jarvis.Memory.SQLiteStore` that delegates every call. It adds a layer without a second implementation need.
- **Consequences:** The behavior stays intentionally small: `recall/3` and `remember/1`. Forget and supersede remain direct context operations.
- **Governs:** R1, R4, R6, R7, U1.

#### KTD4 — Keep synchronous store effects for this proof

- **Decision:** Recall and remember continue inside the routed Action. The store is the only state changed by a memory operation.
- **Reason:** The user requested a thin local test. A runtime process, operation journal, and completion Signals would test a different and larger contract.
- **Rejected alternative:** Return stateless directives and write after commit. That requires asynchronous accepted-versus-completed semantics and recovery policy.
- **Consequences:** A SQLite write can complete before the Jido turn commits. If a later turn stage fails, the record can exist even when the caller receives a failure. This is an accepted local-spike limit and must remain documented.
- **Governs:** R1, R2, R4, R7, U1 and the failure-path tests.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| `lib/jarvis/memory/store.ex` | Does not exist. | Define the local `recall/3` and `remember/1` behavior. | Keep return shapes equal to `Jarvis.Memories`. |
| `lib/jarvis/memories.ex` | Concrete SQLite context. | Declare the store behavior; keep implementation unchanged. | No schema, query, or caller change. |
| `lib/jarvis/plugins/memory.ex` | Owns `:memory` state and counter directives. | Validate store and namespace options, prepare config, expose config-backed helpers, and retain two routes. | Removing state affects assessment and status callers. |
| `lib/jarvis/agent.ex` | Loads the Plugin without options. | Configure `Jarvis.Memories` and `"jarvis"`. | Agent snapshots no longer contain `:memory`. |
| `lib/jarvis/actions/memory.ex` | Reads `agent_state.memory` and returns counter directives. | Read prepared config and return only the store result. | Preserve Signal input and reply shapes. |
| `lib/jarvis/actions/assess_purpose.ex` | Reads memory state and returns memory and VSM directives. | Recall through prepared config and return only the VSM directive. | Preserve `memory_ids` and stale-schedule handling. |
| `lib/jarvis/runtime.ex` and `lib/jarvis/chat/tools/status.ex` | Expose memory counters as Agent status. | Return and describe schedule and VSM state only. | This is a local, unpublished status shape change. |
| Memory and Plugin tests | Assert SQLite behavior and memory counters. | Prove store substitution, no Agent memory state, unchanged FTS5 behavior, and no memory write from information Signals. | Replace counter evidence with direct store evidence. |
| README and active plans | Describe Plugin-owned memory state and counts. | Describe the stateless configured Plugin and synchronous effect limit. | Documentation must match the final implementation. |

No migration, dependency, UI, or asset change is planned.

### Implementation Units

#### U1 — Convert the local memory Plugin to a configured store boundary

- **Outcome:** The main Agent recalls and stores SQLite memory through a stateless, configured `Jarvis.Plugins.Memory`, and all current consumers and documentation agree with that boundary.
- **Requirements:** R1-R7.
- **Dependencies:** None.
- **Affected surfaces:** All files and interfaces in the change-surface table. Tests stay with the behavior because partial removal of memory state would break purpose assessment.
- **Implementation direction:**
  1. Add `Jarvis.Memory.Store` with callbacks matching the current `Jarvis.Memories.recall/3` and `remember/1` return shapes.
  2. Declare the behavior in `Jarvis.Memories` without changing its SQLite or FTS5 code.
  3. Change `Jarvis.Plugins.Memory` to accept `:store` and `:namespace` as Agent-owned Plugin options. Validate a non-empty namespace and a loaded store module that exports both callbacks.
  4. Add `prepare/2` and a context helper that reads the prepared configuration. Remove `Memory.Record`, `state_spec/1`, `directives/1`, `reduce/2`, and `dispatch/4`.
  5. Configure the main Agent with `Jarvis.Memories` and namespace `"jarvis"`.
  6. Change the recall and remember Action branches to use the prepared store configuration. Preserve current validation, result fields, and error mapping.
  7. Change purpose assessment to use the same prepared configuration and return only the VSM directive. Preserve the assessment result and stale-schedule behavior.
  8. Remove memory state from runtime status and update the status tool description.
  9. Add a small test store that proves the Action uses the configured module. Update integration assertions to inspect SQLite state instead of counters. Assert that the main Agent snapshot has no `:memory` key.
  10. Update README and the active plans. State that synchronous remember can outlive a later turn failure.
- **Test scenarios:**
  - A configured fake store supplies recall output and remember IDs through the Action.
  - Missing, invalid, or incomplete store configuration returns a validation or execution error before a store call.
  - Main-Agent remember and recall Signals use namespace `"jarvis"` and keep their reply shapes.
  - Purpose assessment records matching memory IDs and increments only VSM assessment state.
  - An information Signal does not add, replace, or forget a memory record.
  - Agent status and snapshot contain schedule and VSM state but no memory state or counters.
  - Existing namespace isolation, replacement exclusion, forgetting, class filtering, five-result limit, chat provenance, and memory LiveView behavior remain passing.
- **Verification:** Run the focused tests, then the repository gates in the Verification Contract.
- **Completion signal:** All R1-R7 scenarios pass, repository documentation names the new boundary, and the final Agent definition has no Plugin-owned `:memory` field.

### Work Graph

- Initial frontier: U1.
- Parallel groups: None. The change is one small behavior slice.
- Critical path: U1.
- Final integration unit: U1.

### Verification Contract

Run all commands from `/Users/mhostetler/Source/Jido/spikes/jarvis`.

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Store and Action behavior | U1 | Focused store, memory Action, and Plugin route tests | Configured store is used; reply shapes match; no memory state exists. |
| SQLite regression | U1 | Existing `Jarvis.MemoriesTest` | FTS5 recall, namespaces, lifecycle filters, classes, and limits pass. |
| UI regression | U1 | Existing memory LiveView tests | Manual create, replace, forget, validation, and Markdown rendering pass. |
| Agent integration | U1 | Plugin and control tests | Purpose assessment and main Agent composition pass without memory state. |
| Repository | U1 | Compile, format, and full tests | No warning, formatting error, or test regression. |

Focused checks:

```sh
mix test test/jarvis/memories_test.exs test/jarvis/plugins_test.exs test/jarvis_web/live/memories_live_test.exs
```

Repository gates:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

Requirement traceability:

| Requirement | Units | Verification |
| --- | --- | --- |
| R1 | U1 | SQLite rows and recall tests are the source-of-truth evidence. |
| R2 | U1 | Agent definition and snapshot tests show no `:memory` field or directives. |
| R3 | U1 | Fake-store Action tests and invalid-configuration tests. |
| R4 | U1 | Main-Agent remember and recall route tests. |
| R5 | U1 | Scheduled assessment test with asserted memory IDs. |
| R6 | U1 | Chat preparation and memory LiveView regression tests. |
| R7 | U1 | Scoped diff plus unchanged dependencies and migrations. |

### Rollout and Recovery

This is a local uncommitted spike. No deployment or data migration is required. Existing SQLite records and FTS5 indexes remain compatible. If the change fails verification, revert only the implementation change; no data recovery step is expected because the schema and stored meanings do not change.

### Risks and Assumptions

- **Accepted risk:** A synchronous remember call can write SQLite before a later Agent turn stage fails. This local proof does not claim atomic Agent commit and store mutation.
- **Risk:** Removing `state.memory` can silently disable purpose assessment if its pattern match is not migrated. The assessment test must assert recalled IDs, not only turn count.
- **Risk:** Tests can pass while the Action still hard-codes `Jarvis.Memories`. The fake-store test must prove configured-module use.
- **Assumption:** The current Jido prepared Plugin input contract continues to carry module atoms and namespace strings into Action context. The current Memory Plugin uses this pattern.
- **Assumption:** No supported external caller depends on memory counters in `Jarvis.Runtime.status/0`. The repository search found only local tests and the status tool description.

### Open Planning Decisions

None. Extraction, vector search, asynchronous mutation delivery, and more memory routes are deferred until this local proof gives evidence for their contracts.

### Definition of Done

- `Jarvis.Memory.Store` exists with only recall and remember callbacks.
- `Jarvis.Memories` implements the behavior without FTS5 or schema changes.
- `Jarvis.Plugins.Memory` is stateless and has no runtime process.
- The main Agent configures the store and namespace explicitly.
- Memory routes and purpose assessment use prepared Plugin configuration.
- Runtime status contains no memory state or counters.
- Existing direct chat and LiveView memory behavior remains unchanged.
- Focused checks and all repository gates pass.
- README and the active plans describe the implemented boundary and its synchronous-effect limit.
- No dependency, migration, embedding, vector, package, commit, or remote change is included.

### Planning Sources

- [Jido Plugin contract](../../../../jido_core/jido/lib/jido/plugin.ex)
- [Local Memory prepared-configuration pattern](../../lib/jarvis/plugins/memory.ex)
- [Current main Agent](../../lib/jarvis/agent.ex)
- [Current purpose assessment](../../lib/jarvis/actions/assess_purpose.ex)
- [Current Plugin tests](../../test/jarvis/plugins_test.exs)
- [Current memory tests](../../test/jarvis/memories_test.exs)

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-14-0702-thin-store-backed-memory-plugin-plan.md`
- HTML: not requested
- Beadwork: not requested
