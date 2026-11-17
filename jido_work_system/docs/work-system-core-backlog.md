# Work System Core Backlog

Status: Proposed. No item in this backlog is approved for implementation yet.

## Strong direction

Do not add more behavior to the current resource model.

Keep the 14 stories as characterization tests. Build a smaller command-driven core beside the current model. Move each story to the new core. Delete the old resources after all stories and negative tests pass.

Do not build a compatibility layer. This spike has no public package API.

## Core design rules

The new core must enforce these rules in domain commands, not only in the scenario runner or trace checker:

1. One human remains accountable for each root work item.
2. Delegated authority does not transfer accountability.
3. A cell must accept an exact contract revision before work starts.
4. A judgment proposes an effect. It does not apply the effect.
5. Every effect uses a valid grant and expected state revision.
6. A submission is checked against the same contract revision that the cell accepted.
7. A passing check does not close the work item.
8. One closure ends the work item.
9. Cancellation, expiry, decline, failure, and success are different end states.
10. Audit events are append-only.

## Product decisions

The core direction is confirmed in [Product decisions](product-decisions.md). Eight product-policy details remain open there. The backlog remains proposed work and does not become approved because the design direction is confirmed.

## Ordered backlog

### Phase 0 — Prove the current model can fail

#### WS-001 — Add negative model tests

Priority: P0

Add tests that create or attempt these invalid states:

- the wrong cell starts work;
- a check uses an old contract revision;
- a principal without acceptance authority accepts work;
- a tool receipt is forged;
- work expires before the clock reaches the deadline;
- canceled work is marked complete;
- a child cell works without an assignment;
- a changed four-part contract passes with three-part evidence.

Done when each invalid state is rejected by the domain boundary. A trace checker alone is not sufficient.

#### WS-002 — Freeze the 14 stories as characterization fixtures

Priority: P0

Define the expected final state, important events, and rule results for each story. Keep UI projection checks separate from domain checks.

Done when the stories can run against either the old or new model and compare the same business result.

Depends on: WS-001.

#### WS-003 — Define typed lifecycle states and invariants

Priority: P0

Write the allowed states and transitions for work items, assignments, execution attempts, effects, checks, and closures. Remove free-form status strings from the new core.

Done when every transition has a named command, allowed source state, target state, actor rule, and revision rule.

Depends on: DEC-01 through DEC-06.

### Phase 1 — Build the core spine

#### WS-010 — Add Principal and WorkCell

Priority: P0

Create one acting identity model for humans, work cells, and services. Model a work cell as a principal with purpose, optional parent cell, capabilities, and operating policy.

Human outcome accountability belongs to the work item. A work cell can have an administrative steward, but that steward is not automatically accountable for each job.

Do not treat an LLM, HTN planner, behavior tree, or rule set as a principal. These are procedures used by a principal.

Done when commands can name one exact actor and the system rejects anonymous actions.

#### WS-011 — Add WorkItem and immutable ContractRevision

Priority: P0

A work item represents one goal. Each contract change creates a new immutable revision with:

- objective;
- deliverable specification;
- acceptance criteria with stable IDs;
- constraints and resource limits;
- due time and expiry policy;
- escalation and repair policy;
- accountable human; and
- acceptance policy.

Done when an active cell must accept a new revision before it can continue after a contract change.

Depends on: WS-003, WS-010.

#### WS-012 — Add immutable AuthorityGrant

Priority: P0

Record issuer, grantee, work and contract scope, permitted actions and resources, machine-readable limits, validity time, revocation, and subdelegation rights.

Support Advise, Operate, and Represent ceilings. The root grant sets a maximum delegation depth with a default of 3. Revocation cascades through descendant grants.

A new permission creates a new grant or grant revision. Do not edit historical authority.

Done when every state-changing command can prove which valid grant allowed it.

Depends on: WS-010, WS-011.

#### WS-013 — Replace Delegation with Assignment

Priority: P0

An assignment is an offer from a human or cell principal to one work cell. It names the work item, contract revision, sender, receiver, terms, authority grant, and expiry time.

States: `offered`, `accepted`, `declined`, `withdrawn`, and `expired`.

A declined assignment does not close the work item. The owner can reassign or close it.

Done when human-to-cell and cell-to-cell handoffs use the same contract.

Depends on: WS-010 through WS-012.

#### WS-014 — Replace WorkExecution with ExecutionAttempt

Priority: P0

One execution attempt belongs to exactly one accepted assignment.

States include planning, running, waiting, blocked, checking, repairing, submitted, succeeded, failed, canceled, and expired.

Done when work cannot start without an accepted assignment and cancellation never becomes successful completion.

Depends on: WS-013.

#### WS-015 — Add named domain commands

Priority: P0

Move lifecycle rules out of `ScenarioRunner`. Add explicit commands for contract revision, grant, assignment, acceptance, work start, block, resume, submit, check, repair, cancel, expire, and close.

Each command checks actor, current revision, state, authority, preconditions, and idempotency.

Remove generic update and destroy actions from the new core.

Done when invalid state changes cannot be made through public resource actions or `Store` helpers.

Depends on: WS-010 through WS-014.

### Phase 2 — Make judgment explicit

#### JUD-001 — Specify the judgment boundary

Priority: P0

Use this rule:

> Judgment is required when current facts, the accepted contract, explicit policy, and a fixed tie-break rule do not determine one valid next action.

Schema validation, authority checks, state transitions, arithmetic, persistence, objective checks, fixed retry rules, and accepted plan-step execution are deterministic work. Do not record them as judgment.

Done when each current story labels every choice as judgment or deterministic work and the labels pass review.

#### JUD-002 — Replace Judgment, Decision, and JudgmentMethod with one aggregate

Priority: P0

Use one immutable judgment request and one immutable result.

The request must name:

- work item, attempt, contract revision, state revision, trigger, and question;
- exact input references and input digest;
- observations with source, time, and evidence;
- stable option IDs with preconditions, expected results, risks, and proposed effects; and
- authority mode: advisory or binding.

The result must be `choose`, `abstain`, `need_input`, or `escalate`. A choice references one stable option ID. It records basis, assumptions, supporting and opposing evidence, uncertainty, risk, procedure identity and version, configuration digest, actor, time, causation, and output digest.

Numeric confidence is optional. If present, its scale and meaning are required.

Done when human, LLM, behavior-tree, HTN, rule, classifier, optimizer, and search adapters can all produce the same judgment result shape.

Depends on: DEC-01, JUD-001, WS-010, WS-011.

#### JUD-003 — Record the human judgments that matter

Priority: P0

Record revision requests, discretionary acceptance, rejection after a passing check, escalation, and repair-versus-stop choices through the judgment contract.

Do not record fixed authority membership or fixed decomposition as judgment.

Done when every discretionary human choice has a judgment record and proposed effect.

Depends on: JUD-002.

### Phase 3 — Separate judgment from effects and results

#### EFF-001 — Replace Mutation with EffectAttempt

Priority: P0

Record assignment, execution attempt, causing judgment or deterministic policy, action, target, expected revision, grant, authorization result, idempotency key, retry relation, status, receipt, error, and compensation.

A retry creates a linked attempt. Tool failure creates a failed effect record. A judgment can only propose this effect.

Done when the executor checks state revision, grant validity, judgment expiry, preconditions, idempotency, and cancellation before applying an effect.

Depends on: WS-012, WS-014, JUD-002.

#### OUT-001 — Add immutable Submission and Evidence

Priority: P0

A submission is one immutable version of the proposed result for one execution attempt and contract revision.

Evidence is an immutable fact or artifact with producer, provenance, capture time, digest, and stable reference. Evidence can come from an effect, person, test, or external source. It does not require a mutation.

Done when a changed contract cannot reuse an old submission or claim old evidence as proof of new criteria.

Depends on: WS-011, WS-014, EFF-001.

#### OUT-002 — Replace Evaluation with Check

Priority: P0

A check names one submission, one contract revision, stable acceptance criteria, checker principal, procedure identity and version, evidence used, per-criterion results, findings, and a result of passed, failed, or inconclusive.

A check does not close work.

Done when the late-change story cannot pass a four-part contract with a three-part check.

Depends on: OUT-001, WS-010.

#### OUT-003 — Replace Outcome and terminal event names with Closure

Priority: P0

Create exactly one closure for each closed work item. Reasons include accepted, rejected, canceled, expired, failed, abandoned, and superseded.

Acceptance requires the current submission, required passing checks, valid acceptance authority, and a judgment when discretion is needed. Cancellation and expiry do not require a submission or check.

Done when decline closes only the assignment, closure ends the work item, and all active attempts end with the matching reason.

Depends on: DEC-02, DEC-03, WS-011, WS-014, OUT-002, JUD-003.

#### AUD-001 — Add append-only domain events

Priority: P0

Each state-changing command emits events with aggregate revision, actor, subject, cause, correlation, command ID, time, and old and new state references.

The scenario cursor stays outside the domain. One command can emit more than one event.

Done when audit history cannot be changed or deleted through public actions.

Depends on: WS-015.

### Phase 4 — Move the stories and harden the system

#### MIG-001 — Run the 14 stories through new commands

Priority: P1

Keep the stories as orchestration only. They must call the same named commands that production callers use.

The specialist story must create a child work item and a true cell-to-cell assignment.

Done when every story has business-result parity and no story code writes domain state directly.

Depends on: all P0 core items.

#### TEST-001 — Add concurrent command tests

Priority: P1

Test simultaneous assignment acceptance, contract change, cancellation, effect application, submission, check, and closure commands against the same expected revision.

Done when exactly one conflicting command succeeds and all losing commands return a stable revision error without partial writes.

Depends on: WS-015, AUD-001.

#### TEST-002 — Add a simulated clock

Priority: P1

Use a controlled clock for assignment expiry, work expiry, deadlines, judgment validity, grant validity, waits, and retry delay.

Done when no test needs the wall clock and early expiry is impossible.

Depends on: WS-012 through WS-015.

#### TEST-003 — Add fault injection

Priority: P1

Inject tool timeout, unknown tool result, database failure, checker failure, duplicate delivery, and retry exhaustion.

Done when each fault creates durable state and a safe retry, escalation, compensation, or closure path.

Depends on: EFF-001, OUT-002.

#### TEST-004 — Add seeded input variation

Priority: P1

Vary contract size, facts, criteria, grant limits, due times, retry limits, repair limits, and child-work depth with a saved seed.

Done when every failed run can be replayed from its seed and trace.

Depends on: MIG-001.

#### TEST-005 — Stream pressure traces

Priority: P2

Write each trace as its run finishes. Do not keep every full trace in memory.

Done when a large pressure run has bounded memory use and still produces a summary plus one file per trace.

### Phase 5 — Delete accidental complexity

#### CLEAN-001 — Remove old duplicate resources

Priority: P1

After story parity and negative tests pass, delete:

- `Decision` and the fixed `JudgmentMethod` catalog;
- old `Task`, `Delegation`, `WorkExecution`, and `Outcome` lifecycles;
- `Mutation` and `Evaluation`; and
- old generic state-changing store paths.

Done when no new-core command reads or writes these resources.

Depends on: MIG-001, TEST-001 through TEST-004.

#### CLEAN-002 — Move extension concepts out of the core

Priority: P1

Move these concepts to optional extensions unless a core invariant requires them:

- roles and general organization accountability;
- tool catalogs;
- workspaces;
- knowledge stores;
- VSM identifiers and topology helpers;
- queue and capacity policy;
- planner products; and
- artifact storage.

Keep only direct human accountability, principal identity, work-cell parent links, and capability or policy references in the core.

Done when the core can run the 14 stories without loading an extension package.

#### CLEAN-003 — Remove scenario state from the domain

Priority: P1

Keep `ScenarioRun`, cursor, visual projection, and story metadata in the simulation application. Do not validate domain integrity from scenario position or event count.

Done when production commands have no dependency on scenario modules.

Depends on: MIG-001.

## Recommended first delivery slice

Do not start by creating all new tables.

The first delivery slice should contain:

1. DEC-01 through DEC-06 decisions.
2. WS-001 negative tests.
3. WS-003 typed lifecycle specification.
4. WS-010 through WS-015 for one simple success path.
5. AUD-001 append-only events.
6. One original success story running through the new commands.

This slice proves the command boundary and core lifecycle before judgment, tools, submissions, checks, and repair add more concepts.

## Backlog items that must not be combined

Keep these as separate changes so failures have a clear cause:

- domain command enforcement and scenario migration;
- judgment recording and effect execution;
- submission creation and checking;
- closure policy and UI projection;
- concurrency testing and feature development;
- core resource deletion and extension extraction.
