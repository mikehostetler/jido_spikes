---
title: Multiple Durable Work Cells in Kura
type: implementation-plan
date: 2026-11-17
last_reviewed: 2026-11-17
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Multiple Durable Work Cells in Kura

## Goal Capsule

- **Objective.** Show two independent Durable Work Cells in one Kura app. Restart one during work and recover its result.
- **Means.** Use one native Jido VSM topology per cell, AshSqlite for durable work records, and a separate local workspace for each cell.
- **Authority.** This request authorizes the plan. Execution requires separate local implementation authority.
- **Stop conditions.** Stop and surface a failure if Kura cannot identify the owning cell, establish control approval, or reconcile a saved effect.
- **Next executor.** The Kura implementer.

## Product Contract

### Summary

Kura is a local Phoenix showcase for the Jido Work System. The basic cell must work as a repeatable unit. Two cells must be able to run the same kind of task independently.

### Problem Frame

The Phoenix and Ash foundation starts one Jido instance. Kura still needs durable cell identity, cell-specific execution and workspace access, and a direct way for the operator to see recovery.

### Actors

- The local operator assigns the work and accepts a verified result. Accountability stays with that human.
- Each work cell owns its assigned work and has its own Jido VSM activation.
- A deterministic checker compares the result with the accepted contract and records evidence.

### Requirements

- **R1.** Host two or more independently addressable cells, with separate work, workspaces, and status.
- **R2.** Run a basic work contract through the cell's native Jido VSM control path. Require both a successful control outcome and a matching Kura work grant before a write.
- **R3.** Preserve cell identity, the work contract, the workspace artifact, and progress across interruption. Recover a pending write without applying it twice.
- **R4.** Show the active contract, control evidence, output, check, and acceptance for each cell in Phoenix. Keep the app local and unauthenticated.

### Key Flows

The operator selects a cell, assigns a demo contract, and starts the run. Kura records the exact accepted contract. The selected cell processes the VSM request. Kura checks the control result and the contract grant, applies a bounded effect, and records the check. The operator accepts the verified result.

On restart, Kura loads the saved cell and run. The operator selects **Resume**. Kura reconciles the recorded effect against the workspace before it moves to the next step.

### Acceptance Examples

Start the same demo in **Cedar** and **Pine**. Each cell writes a report from its own fixture input. Stop Cedar after it writes its report and before it records the receipt. Pine finishes. Restart Cedar and resume the same run. Kura recognizes Cedar's report, records one receipt, and presents one verified result for acceptance.

### Success Criteria

The two runs can overlap, and stopping one cell leaves the other cell ready. Restarting the application preserves both cell IDs and both work histories. The screen shows the difference between a passing check and the operator's acceptance.

### Scope Boundaries

Use one task type, one open run per cell, a fixed write grant, one application node, and a deterministic worker. Defer cell-to-cell delegation, arbitrary commands, model calls, workspace repository integration, and the Jido skill loader. The skill loader belongs at the worker boundary in a later slice.

### Key Decisions

The demo uses saved cell IDs with replaceable Jido activations, operator-triggered resume, and operator-only acceptance. These are proposed defaults for Kura's demo. The Work System's broader work-cell identity policy remains open.

### Rejected Alternatives

A two-cell demo with only two names in the database would leave runtime isolation, workspace isolation, and recovery untested.

### Dependencies

Use the existing pinned Jido V3, Jido VSM V3, AshJido V3, and AshSqlite dependencies.

### Outstanding Questions

No additional product decision is needed to specify this demo. Work System identity lifetime remains an open product question for Mike (OPEN-003).

### Sources

- [Kura foundation](../../README.md)
- [Work System product decisions](../../../jido_work_system/docs/product-decisions.md)

## Planning Contract

### Product Contract Preservation

This direct-request plan carries forward local operation, a bounded workspace, durable work, separate verification, and human accountability. It applies the Work System rule that separate cells never share one execution attempt.

### Current System

Kura supervises its AshSqlite repo, a named Jido instance, and the Phoenix endpoint. Its Ash domain has the AshJido extension. Section 9 demonstrates a native VSM work loop and a durable ledger for one cell. Its runtime uses a fixed cell ID and scans resident agents by role, which can select the wrong agents when two cells have the same topology.

### Target System

| Owner | Responsibility |
| --- | --- |
| Ash and SQLite | Cell ID and workspace reference, accepted contract, run revision and phase, effect intent and receipt, check evidence, operator decision |
| One shared `Kura.Jido` instance | Separate root activation and owned topology for each cell |
| Native `Jido.VSM.Cell` | Two S1 operations named `delivery` and `readiness`, with the standard S2 through S5 roles, including S3* |
| Kura executor and checker | Grant and revision checks, the file effect, recovery, and a separate check of the submitted artifact |
| Phoenix LiveView | Cell list and detail, run and resume controls, evidence, and acceptance |

### Key Technical Decisions

- **KTD1. One definition with many activations.** Use a module-based standard cell and start each top-level root under `Kura.Jido` with a stable ID derived from the cell UUID. Resolve members through that root's topology or verified ownership. One Jido instance per cell would add instance lifecycle and configuration without serving the isolation requirement. The topology dependency must pass a two-root isolation test before U2. Governs R1 and U1–U3.
- **KTD2. VSM controls the run. Kura owns writes.** Send the native typed request to the selected root with target `delivery`. Use the standard roles and a small deterministic adapter. Give the S3 delivery command a value that includes its request ID. Wait for that exact command in the owned delivery member's committed `last_command` field. The `readiness` operation can report readiness in a separate, read-only request. S3* audits control messages. The separate checker checks the actual artifact after the effect. The Kura work grant still applies immediately before a workspace effect. Governs R2 and U2.
- **KTD3. Use a durable intent and reconcile the file.** Store the target path, before digest or absent marker, deterministic output digest, and effect ID before the write. Use a file replacement in the same directory and a unique receipt per effect. On resume, a matching output digest recovers the receipt, a matching precondition permits one retry after fresh control and grant checks, and any other state blocks for operator review. The file and SQLite have separate commit boundaries. Governs R3 and U3.

### System Boundaries and Change Surface

- **Domain.** Add `WorkCell` and `WorkRun` to `Kura.Work`. Add a small effect record for the intent and receipt. A run belongs to exactly one cell and has a saved contract, revision, check, and acceptance. Enforce one open run per cell with a database constraint. Commit each phase change against its expected revision. Accept only the current verified artifact digest.
- **Activation.** Start or find the root by stable ID using Jido. Resolve a live handle on demand. Await readiness before dispatch. One bounded, monitored runner per cell keeps requests serial within a cell and allows concurrent work across cells. Confirm the prior runner has stopped before a replacement reconciles or retries a write. Recreate roots on demand after app restart and leave effects paused until the operator resumes.
- **Control.** Tie evidence to cell, run, and a fresh request ID for each control attempt. Persist the exact committed command value as the control receipt. Report audit and policy status separately from this receipt. A root's committed turn alone shows request handling. Role counters and separate latest-value fields cannot prove command correlation. Match the current revision before recording a result. Timeout or stop before execution leaves the run resumable. Ignore late results after the revision advances. Route the demo through explicit domain commands. AshJido remains available for future selected action exposure.
- **Workspace.** Create a local directory from the cell UUID, with read-only fixture input and one fixed output path per run. Accept no paths or commands from the browser. Check confinement at the executor and reject symlinks. The demo checker has read access only. Keep workspace files and SQLite runtime data out of Git.
- **Compatibility.** The change adds Kura tables, runtime components, and routes. It requires no change or release in Jido, Jido VSM, or AshJido. Preserve the current home route. Seed demo cells explicitly or create them idempotently on request.

### Implementation Units

#### U1 — Open two distinct cells

Requirements R1 and R4. Dependencies none. Add the cell resource and migration, the native cell definition, root resolution, and a minimal Phoenix cell list and detail view. Test two roots with the same topology names. Send a request to one and verify only its members respond. Test duplicate activation and stop one root while the other stays ready. Complete when two saved IDs resolve to distinct working topologies.

#### U2 — Run and accept a checked result

Requirements R1, R2, and R4. Depends on U1 for scoped runtime access. Add accepted contracts, a real VSM request and evidence gate, the bounded workspace executor and checker, and the operator's accept action. Record the intent and receipt from the first implementation. Verify two simultaneous runs, stale or foreign control evidence, control timeout, an invalid grant, and a failed check. Complete when both cells produce separate verified results and the operator sees and accepts each one.

#### U3 — Recover the interrupted cell

Requirements R1, R3, and R4. Depends on U2 for the real effect boundary. Add restart and resume handling, digest reconciliation, and an automated fault point at the write-to-receipt boundary. Show the interruption and recovery in Phoenix. Test the interrupted run, stale callbacks, unexpected file content, and an application restart using the same database and workspaces. Complete when the demo recovers Cedar and preserves Pine's result.

### Work Graph

U1 supplies scoped cell identity and runtime access to U2. U2 supplies the durable run and file-effect boundary to U3. The critical path is U1 → U2 → U3.

### Verification Contract

| Gate | Units and requirements | Evidence |
| --- | --- | --- |
| Cell isolation | U1, R1 | Real roots and owned members. A request and stop affect only the selected cell. |
| Work and control | U2, R1–R2, R4 | Two overlapping runs via the normal entry point. Wrong, stale, denied, and timed-out requests produce no file. A failed check prevents acceptance. |
| Recovery | U3, R1, R3–R4 | Kill after the file write. Restart the root and separately restart the app. Resume from the same files and DB. Confirm one receipt and no second file write. Confirm unexpected digest blocks. |
| Final | All | Run the Kura checks below and walk through both cells via Phoenix on loopback. |

Run these from the Kura directory once implementation exists.

```sh
mix setup
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

### Rollout and Recovery

Apply additive schema changes with Kura's local setup command. Test a fresh DB and a copy of an existing development DB. If startup fails, preserve the DB and workspace for inspection. Keep the new tables and workspace files when rolling back code after a demo run.

### Risks and Assumptions

The first risk is cross-cell VSM evidence. Standard role names and counters repeat across roots. Require owned member identity and exact request evidence. The second risk is a crash between file and database commits. Use the digest and receipt tests to show recovery. This design covers one local application node and process or VM restart.

### Open Planning Decisions

The Kura implementer must prove that the pinned topology can resolve member evidence per root in U1. A failure here blocks U2 and requires adjustment to the Kura integration. Mike owns the broader identity policy and delegation decisions after the demo.

### Definition of Done

Both cells run the same demo independently under one instance. A real VSM control path gates each bounded file write. The interrupted cell resumes with one receipt. The operator sees and accepts checked results per cell. Kura's checks pass and its README describes the demo.

### Planning Sources

- [Kura application supervision](../../lib/kura/application.ex), [Ash domain](../../lib/kura/work.ex), and [dependency lock](../../mix.lock)
- [Section 9 VSM integration](../../../section9/lib/section9/viable_work_cell.ex) and [run evidence](../../../section9/RUNS.md)
- Pinned VSM source under `deps/jido_vsm`, especially `cell.ex`, `cell/authoring.ex`, `action/handle_s2_report.ex`, and `action/apply_s3_command.ex`
- Pinned Jido source under `deps/jido`, especially `Jido.start_agent/3`, `Jido.agent_ownership/2`, and `Jido.AgentServer.await_ready/2`

## Adapter Results

- Markdown is the plan in this file.
- HTML and Beadwork were not requested.
