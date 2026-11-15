---
title: Reduce Jarvis to memory, chat, and one VSM review loop
type: implementation-plan
date: 2026-11-14
last_reviewed: 2026-11-14
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Reduce Jarvis to memory, chat, and one VSM review loop

## Goal Capsule

- Objective: Keep only Memory CRUD, simple local-Ollama Chat, and one Timer-driven VSM review that uses Memory and local Ollama.
- Means: Remove the file-operation control plane and replace the broad VSM workflow with one System 4 to System 5 review path.
- Authority: Local changes in `spikes/jarvis`; no commit or push.
- Stop conditions: Stop if the reduced design needs a new public contract or a change outside the Jarvis spike.
- Next executor: A Jido application engineer.

## Product Contract

### Summary

Jarvis is a small local demo with three behaviors: manage memory, chat with a local model, and run a scheduled VSM review that gives the same local model recalled memory.

### Problem Frame

Earlier spikes added a durable file-operation control plane, six custom role workflows, chat tools, status projection, and database records. That code now hides the intended Jarvis demo.

### Actors

- A local user manages memory and chats through Phoenix LiveView.
- The resident Jarvis Agent runs an optional scheduled VSM review.
- Local Ollama supplies model responses.

### Requirements

- **R1:** Keep create, list, replace, forget, and recall behavior for SQLite memories.
- **R2:** Keep one simple streaming Chat Agent that uses local Ollama and recalled conversation memory.
- **R3:** A Timer tick must recall Jarvis memory, enter the VSM through System 4, call local Ollama, pass the result to System 5, and expose the latest completed review.
- **R4:** Keep Timer start, pause, resume, and stale-generation protection without a second loop process.
- **R5:** Remove the file-operation control plane, chat control tools, observation flow, status Plugin, and obsolete UI and database code.
- **R6:** Tests must prove the model boundary without requiring a live Ollama server. A separate live smoke check can prove the local integration when Ollama is available.

### Key Flows

1. Memory: `/memories` -> `Jarvis.Memories` -> SQLite and FTS5.
2. Chat: `/` -> `Jarvis.Chat.Agent` -> recalled memory -> local Ollama -> streamed reply.
3. VSM review: `Jarvis.Runtime.start/2` -> Timer -> memory recall -> VSM S4 model review -> VSM S5 record -> main Agent status.

### Acceptance Examples

- A user creates, edits, and deletes a memory in `/memories`.
- Chat receives a local Ollama answer and includes matching conversation memory in its model input.
- A scheduled review uses matching `jarvis` memory and records the model answer in `Jarvis.Runtime.status/0`.
- Paused and stale timer events do not record a new review.
- No live route or source reference remains for the old control plane.

### Success Criteria

- All three flows have direct tests.
- `mix compile --warnings-as-errors`, formatting, and the full test suite pass.
- `lib/jarvis` has one clear module path for each retained behavior.

### Scope Boundaries

- In scope: local single-node Phoenix, SQLite memory, Jido Agents, Jido Timer, `Jido.VSM.Cell`, and local Ollama.
- Out of scope: arbitrary work execution, file operations, resource leases, durable causal traces, strategy approval, production authorization, and deployment.

### Key Decisions

- Use one fixed local model for Chat and VSM review.
- Use the official Jido inference-client boundary in System 4 so tests can supply an offline client.
- Keep all required VSM roles, but make unused roles passive. This demo exercises only the S4-to-S5 review path.

### Rejected Alternatives

- Keep the control plane as a second demo: rejected because it is not one of the three requested use cases.
- Keep Chat tools that control the main Agent: rejected because Chat must remain simple.
- Call the model outside the VSM: rejected because R3 requires the VSM path to own the review.

### Dependencies

- Local path dependencies on Jido core and `jido_vsm` remain.
- Local Ollama is required only for live Chat and VSM model calls.

### Outstanding Questions

None.

### Sources

- Direct request in this task.
- Current application, Agent, Runtime, Chat, Memory, VSM, LiveView, migration, and test source in this repository.
- Local Jido inference-client and `Jido.VSM.Cell` contracts.

## Planning Contract

### Product Contract Preservation

Direct request preserved without scope change.

### Current System

`Jarvis.Application` starts one resident main Agent through `Jarvis.Bootstrap`. The main Agent has Memory, Status, and Timer Plugins. Its nested VSM has custom code for all six roles, a file-operation workflow, observations, and assessment bookkeeping. Chat has tools that control that main Agent. The control workflow also owns LiveView, Ecto schemas, one migration, and demo workspace configuration.

### Target System

The application keeps the same Repo, Jido instance, PubSub, task supervisor, endpoint, and resident main Agent. The main Agent has only Memory and Timer Plugins plus small review state. Timer events prepare recalled memory before they enter one VSM Cell. System 4 calls the selected inference client with the local Ollama model. System 5 records and returns the review. Chat remains a separate conversation Agent with no tools.

### Key Technical Decisions

- **KTD1 — Direct main-Agent review state.** Remove the Status Plugin and store `reviews` and `last_review` in the main Agent schema. Reason: only one result projection remains. Rejected: a one-use local Plugin. Consequence: the main Agent owns its public status. Governs R3, R5.
- **KTD2 — Small application VSM.** Reuse one passive Agent module for S1, S2, S3, and S3*, and keep active S4 and S5 Agents. Reason: the Cell contract requires all roles, but this demo needs only intelligence and policy. Rejected: six empty custom modules. Consequence: the demo is not a complete operational VSM. Governs R3, R5.
- **KTD3 — Inference in System 4.** Use `Jido.AI.InferenceClient.Selection.client!/1` and `ReqLLM.Context` in the S4 Action. Reason: it keeps local Ollama as the default and supplies a supported offline test seam. Rejected: direct HTTP or a second conversation Agent. Consequence: the timer review blocks the S4 Agent during one model call. Governs R3, R6.
- **KTD4 — Chat has no tools.** Keep only the ReAct model and conversation session. Reason: control tools are outside simple Chat. Rejected: retain tools as optional features. Governs R2, R5.
- **KTD5 — Remove spike-only control data code.** Delete the control schemas and migration instead of preserving compatibility. Reason: this repository has no committed release and the feature is out of scope. Consequence: an existing local database can retain unused tables until it is reset. Governs R5.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| Application startup | Seeds control records and creates a demo root | Start only the resident Agent | Removes obsolete side effects |
| Main Agent | Memory, Status, Timer, control, observations | Memory, Timer, review state | Public Runtime status becomes smaller |
| VSM Cell | File control plus placeholder assessment | S4 model review to S5 | Model calls are asynchronous to the Timer sender but serialized in S4 |
| Chat | Local model plus main-Agent tools | Local model only | Tool requests are removed |
| SQLite | Memory and control tables | Memory tables only | Old local control tables can remain unused |
| LiveView | Chat, memories, control | Chat and memories | `/control` is removed |

### Implementation Units

#### U1 — Reduce the resident Agent and VSM

- **Outcome:** Timer, Memory, S4 local model review, S5 recording, and Runtime status form one end-to-end path.
- **Requirements:** R3, R4.
- **Dependencies:** None.
- **Affected surfaces:** `Jarvis.Application`, `Jarvis.Bootstrap`, main Agent, Runtime, schedule, review Actions, VSM Cell and role modules, and focused tests.
- **Implementation direction:** Keep one Timer job. Pass recalled memory as evidence, not instructions. Record a failed model call as a completed failed review. Ignore stale completions.
- **Test scenarios:** current tick, paused tick, stale tick, recalled memory in model input, success result, model failure, and start/pause/resume.
- **Verification:** Focused Agent and VSM tests with an offline inference client.
- **Completion signal:** `Jarvis.Runtime.status/0` shows the latest valid S5 result.

#### U2 — Reduce Chat

- **Outcome:** Chat uses local Ollama and recalled memory with no main-Agent tool surface.
- **Requirements:** R2.
- **Dependencies:** None.
- **Affected surfaces:** Chat context, Chat Agent, Chat LiveView, and tests.
- **Implementation direction:** Keep conversation activation, streaming, history, and memory input preparation. Remove objective mode and all Chat tool modules.
- **Test scenarios:** page render, memory input preparation, conversation Agent definition has no tools.
- **Verification:** Focused Chat and LiveView tests.
- **Completion signal:** The Chat page has one message flow and no control UI.

#### U3 — Remove obsolete control code

- **Outcome:** No compiled code, route, schema, migration, config, test, or CSS remains for the file-operation control plane or old status and observation paths.
- **Requirements:** R5.
- **Dependencies:** U1, U2.
- **Affected surfaces:** control context, old VSM roles and Actions, Status Plugin, Control LiveView, router, migration, config, tests, README, and CSS.
- **Implementation direction:** Delete only code owned by removed behavior. Keep Memory and Timer migrations and data.
- **Test scenarios:** source search finds no removed module or signal references; router has only Chat and Memories.
- **Verification:** Source search, compile, and full tests.
- **Completion signal:** The project compiles with no old control-plane reference.

#### U4 — Verify and document the reduced demo

- **Outcome:** The README describes only the three core uses and the repository gates pass.
- **Requirements:** R1-R6.
- **Dependencies:** U1, U2, U3.
- **Affected surfaces:** README and the full test suite.
- **Implementation direction:** Document the IEx VSM demo and the live Ollama prerequisite. Keep offline tests deterministic.
- **Test scenarios:** Memory CRUD, simple Chat, Timer/VSM/Memory/model integration, and removed-code search.
- **Verification:** Repository gates below and an optional live Ollama smoke run.
- **Completion signal:** All required gates pass on the final working tree.

### Work Graph

- Initial frontier: U1 and U2.
- Parallel work: U1 and U2.
- Critical path: U1 and U2 -> U3 -> U4.
- Final integration unit: U4.

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Memory behavior | R1 | Memory and LiveView tests | CRUD and recall pass |
| Chat behavior | R2 | Chat and LiveView tests | Simple local-model contract passes |
| VSM review behavior | R3, R4, R6 | Offline inference integration tests | Timer-to-S5 result passes |
| Removal | R5 | `rg` source search and compile | No obsolete reference remains |
| Repository | R1-R6 | Mix gates | All commands pass |

Run from `/Users/mhostetler/Source/Jido/spikes/jarvis`:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
git diff --check
```

When local Ollama and the configured model are available, run one manual `Jarvis.Runtime.start/2` review and inspect `Jarvis.Runtime.status/0`.

### Rollout and Recovery

This is an uncommitted local spike. No data migration or deployment is required. Resetting the local database removes any unused control tables. The application must still start when Ollama is unavailable; only Chat and scheduled model calls can fail.

### Risks and Assumptions

- A review model call can take longer than its timer interval. S4 serializes calls, so use a practical interval for live use.
- The VSM demo uses only S4 and S5. It does not claim to demonstrate full operational control.
- ETS Agent persistence is local to the running VM. SQLite memory is durable.

### Open Planning Decisions

None.

### Definition of Done

- Memory CRUD and recall remain available.
- Chat is one local-Ollama conversation path with memory and no control tools.
- Timer reviews traverse Memory -> VSM S4 -> local model -> VSM S5 -> main status.
- Pause, resume, and stale-generation behavior are tested.
- Old control, status, observation, and objective code is absent.
- Documentation matches the reduced system.
- Required repository gates pass.

### Planning Sources

- Current source and tests under `lib/`, `test/`, `config/`, `priv/repo/migrations/`, and `assets/`.
- Local Jido core inference-client source.
- Local `jido_vsm` application Cell source and examples.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-14-0940-jarvis-core-reduction-plan.md`
- HTML: not requested
- Beadwork: not requested
