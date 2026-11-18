---
title: Learned playbooks for durable work cells
type: implementation-plan
date: 2026-11-17
last_reviewed: 2026-11-17
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Learned playbooks for durable work cells

## Goal Capsule

- Objective — A cell learns a reusable HTN method from work evidence and runs an approved version when a later event matches.
- Means — Use the cell's pulse, the HTN Catalog-backed codec, SQLite, and Loom.
- Authority — This request authorizes the plan. Implementation requires a separate request.
- Stop conditions — The first slice proves selection, learning, approval, reuse, and restart recovery with local fixtures.
- Next executor — A Kura implementer with local write authority.

## Product Contract

### Summary

A Durable Work Cell can accumulate procedures for the work in its role. Its cognitive pulse can propose a playbook from a completed case or improve a current playbook. The cell can run approved procedures on new inputs and wait for further evidence between actions.

### Problem Frame

Cedar saves ReAct traces and can propose a lesson in prose. A later pulse has no approved executable procedure to retrieve from that lesson.

### Actors

Cedar owns the first playbook. Review supplies evidence. The operator reviews candidates and activates a version. Other cells can use the same lifecycle with their own goals, facts, and capabilities.

### Requirements

- **R1** — Store versioned HTN domains in SQLite with trusted action and callback references.
- **R2** — Let the existing pulse propose a domain for a registered task, or a change to an existing version, with evidence links.
- **R3** — Compare the candidate with an established baseline on local fixtures and make the result visible before activation.
- **R4** — Use an approved, applicable playbook on a new event. Resume an active run after restart using its original version.
- **R5** — Preserve cell permissions and keep Cedar's exact-commit CI gate in code.

### Key Flows

- Signal → durable inbox → Cedar pulse → applicable approved playbook → Loom run or wait.
- Case closure → same pulse → candidate → fixture replay → operator approval → new active version.

### Acceptance Examples

On the existing detailed CI failure, the improved method uses the assertion evidence directly. On a second fixture with only a failure summary, it asks Review a specific question. Review then supplies an assertion detail that Cedar did not receive in the CI snapshot. A restart during that wait preserves the run and produces one accepted reply. A stale CI pass stays open under both playbook versions.

### Success Criteria

The dashboard shows the source evidence, candidate method diff, baseline and candidate outcomes, approval, version used on the next case, and recovered wait. A second test cell can register a different task and use the same interfaces without changes to the lifecycle code.

### Scope Boundaries

Use Kura and local fixtures. Hozen stays disconnected. The first live candidate changes one method in Cedar's seeded playbook. The candidate contract also permits a first version for a registered task, which starts without an active playbook.

### Key Decisions

A role describes the work. A task registration lists eligible signals, typed facts, and capabilities. An approved playbook describes how to do one task. A case or run retains the evidence for a specific execution.

### Rejected Alternatives

Whole-domain evolution can explore more alternatives. This slice needs a bounded change so the fixture comparison can identify which method caused the result.

### Dependencies

The separate HTN codec chat owns the safe domain envelope. Its confirmed API and dependency checks gate the storage unit. Loom requires Elixir 1.19 in the inspected checkout. Use one compatible Jido v3 revision across Kura, HTN, and Loom.

### Outstanding Questions

The codec chat owns the final envelope API and Catalog registration shape. Confirm these before binding Kura to that API. The rest of the plan uses the versioned portable domain contract.

### Sources

- [Cedar definition](../../lib/kura/cells/cedar.ex)
- [Cedar pulse](../../lib/kura/cell/cognition.ex)
- [Maintenance coordinator and CI gate](../../lib/kura/maintenance.ex)
- [Fixture snapshots](../../priv/maintenance/ci_snapshots.json)

## Planning Contract

### Product Contract Preservation

The requirements above derive from the direct request and the accepted Cedar example.

### Current System

The maintenance coordinator saves each signal in the Ash case record. A task runs the general pulse. Kura saves its trace and removes the pending item together. Cedar can request Review, and the closure pulse can write a proposal in prose. The code gates closure on passing CI for the tracked head and a different commit from the original failure.

### Target System

Given a cell ID, a registered task, and an event, a pulse receives the eligible approved entrypoints. Eligibility depends on the event type, required facts, and the cell's capabilities. The pulse can select one of those entrypoints or continue ordinary work. Code rechecks eligibility before starting the run. For an in-flight wait, route a matching signal to the existing run.

### Key Technical Decisions

- **KTD1 — Store immutable versions.** Save cell ID, task key, version, base version, entrypoint, codec document, and evidence references. Keep approval and active version in separate metadata. That makes it possible to compare candidates and recover a pinned run. Applies to R1, R2, and U1.
- **KTD2 — Learn within a registered task.** Give the model the role, bounded case evidence, current version, and permitted symbolic actions and callbacks. In the first slice accept one structured method edit against a base version. Validate and encode in code. An initial draft can select a root task and compose existing actions within the same registration. Applies to R2, R5, and U2.
- **KTD3 — Replay before promotion.** Replay means a fresh run on fixture inputs, with fresh projected state and fixture responders. Run the baseline and the candidate through Loom and compare method choices, actions, waits, and outcome assertions. Track recovery of an existing run separately. Applies to R3, R5, U3, and U4.
- **KTD4 — Persist execution and correlate work.** Pin the playbook version and run ID when a run starts. Save Loom's run transition, events, and snapshot atomically. Persist an intent before dispatching a child request. Correlate replies by cell, run, and wait ID so replay after restart does not accept the same reply twice. Applies to R4, R5, and U3.

### System Boundaries and Change Surface

| Surface | Planned contract |
| --- | --- |
| Cell definition | Register a task key, eligible signals, typed input facts, and allowed capabilities. Maintenance facts and actions stay in the Cedar registration. |
| Pulse and inbox | Link the proposal to the triggering pulse and case evidence. Retry an interrupted proposal with the same identity. A failed or invalid proposal leaves the active version intact. |
| HTN and Catalog | Decode a supported envelope with the registry for that cell. Resolve only registered references. Check capabilities at approval and before any action runs. |
| Loom and SQLite | Resolve the run's pinned playbook at load. Persist supported runtime data through Loom's storage interface. Map external waits to Kura inbox signals. Keep CI closure outside the action registry. |
| Dashboard | Show pending work, invalid or failed candidates, method diff, replay evidence, approval, selected method, version, and wait or resume state. |

### Implementation Units

#### U1 — Save and load a playbook version

**Outcome and requirements.** R1, R5. Add a local SQLite version store and seed Cedar v1. Confirm the codec and narrow dependency set first. Use the cell's Catalog for decoding. Test a round trip, an unknown reference, and a denied cross-cell lookup. Complete when a reload yields the same valid Loom input and an invalid document cannot enter the active set.

#### U2 — Produce a candidate from a pulse

**Outcome and requirements.** R2, R5. Extend the existing pulse and closure path with a structured proposal for the registered task. Save its base version, originating pulse, evidence links, and validation result. Use one bounded proposal attempt per closure in this slice. Test a supported edit, a new task draft, a duplicate trigger, and a request for an unavailable action. Complete when each trigger has at most one saved candidate and its source evidence is visible.

#### U3 — Run a pinned playbook and resume a wait

**Outcome and requirements.** R4, R5. Run approved Cedar v1 from an eligible signal. Use Loom's storage adapter boundary and the Kura inbox for Review replies. Add a second test cell with a different registered task. Test wrong-wait and duplicate signals, restart during a wait, and a version change during a run. Complete when a restarted run continues on its original version and accepts one matching reply.

#### U4 — Compare, approve, and reuse

**Outcome and requirements.** R3, R4, R5. Replay v1 and the candidate with isolated fixture inputs through the same runner. Save replay results and make promotion conditional on current base version and passing assertions. Update the active version in one transaction. Test rejection on a failed replay or stale base. Complete when a fresh event selects the approved v2 and the dashboard shows its change in behavior.

### Work Graph

U1 is first after the codec contract and compatibility check. U2 and U3 can proceed in parallel after U1. U4 requires both the candidate contract from U2 and the runner from U3. U4 is the final integration proof.

### Verification Contract

| Gate | Proof |
| --- | --- |
| R1, R5 | Codec round trip and rejection tests. The same domain plans and executes the local fixture after reload. |
| R2 | A real closure pulse produces one structured candidate with evidence. Offline tests cover invalid output and repeated delivery. |
| R3, R5 | Both versions keep the stale CI pass open. The candidate skips redundant Review on the detailed failure and requests it on the sparse failure. |
| R4 | Restart Phoenix with a Review wait open. Match the same run ID, version, and wait ID. Verify one accepted reply and later use of v2 on a new case. The second registered task also runs through the common interface. |

Run the existing Kura checks from the Kura directory. Verify the codec contract in the owning HTN package before running the Kura consumer check. Use the local dashboard for the model-backed acceptance run.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

### Rollout and Recovery

Add the tables beside the current case store. Keep existing case and trace rows readable without a playbook version. Seed one approved v1 for new cases. If a candidate regresses, restore the active pointer to the previous approved version. Existing runs retain their pinned version and event history.

### Risks and Assumptions

Two fixtures prove the learning and reuse path for this example. They give limited evidence about delegation quality on unseen failures. Record failures from decode, binding, and replay in the dashboard. An interrupted read-only model call can repeat. A completed proposal or accepted child reply is recorded once.

### Open Planning Decisions

Package owner to confirm the codec API and supported envelope version before U1. Kura implementer to verify the chosen Jido v3 revision against the HTN, Loom, and Kura lock constraints. The playbook storage model does not depend on the final JSON field names.

### Definition of Done

From the dashboard, an operator can inspect Cedar's learned candidate, compare it with v1, approve v2, and see Cedar use it on a new fixture case. A waiting Loom run recovers after restart. Both versions preserve the exact-commit CI gate. Checks pass, and the Kura README describes the local demo.

### Planning Sources

- [HTN learning API](../../../../jido_htn/jido_htn/lib/jido_htn/learning.ex)
- [HTN playbook contract](../../../../jido_htn/jido_htn/lib/jido_htn/playbook.ex)
- [Loom run and wait design](../../../../jido_htn/jido_loom/PLAN.md)
- [Loom reviewed playbook check](../../../../jido_htn/jido_loom/lib/jido_loom/playbooks.ex)
- [Loom storage behavior](../../../../jido_htn/jido_loom/lib/jido_loom/storage/storage.ex)
- [Kura verification commands](../../README.md)

## Adapter Results

Markdown is canonical. This plan has one Markdown artifact.
