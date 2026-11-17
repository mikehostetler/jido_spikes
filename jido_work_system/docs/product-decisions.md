# Work System Product Decisions

Status: Confirmed shared design concept on 2026-11-17.

This document records the product decisions from the Work System design interview. These decisions guide the replacement core. They do not approve backlog implementation.

## Plain-language product contract

Mike has a job that needs a result. The job becomes a work item with a clear contract. Mike gives a work cell authority to do the job. The cell accepts the exact contract before it starts.

When the right next action is not determined by facts and rules, the cell makes a judgment. The judgment proposes an action. A separate executor checks authority and applies the action.

The cell submits a result. A checker checks that result against the same contract. The work closes only under the contract's acceptance policy.

## Confirmed decisions

### PD-001 — Accountability belongs to the work item

Each root work item has exactly one accountable human. A child work item inherits that human unless accountability is explicitly transferred.

A work cell can have an administrative steward, but that steward is not automatically accountable for every job performed by the cell.

### PD-002 — Accountability transfers only between humans

The current accountable human can offer accountability to another human. The new human must explicitly accept it.

Software cannot become the accountable party. Existing grants become blocked until the new accountable human ratifies or replaces them. Earlier actions remain tied to the accountable human at the time of the action.

### PD-003 — Principals act; procedures help them decide

Humans, services, and work cells are principals.

An LLM, HTN planner, behavior tree, rule engine, classifier, optimizer, or search system is a procedure used by a principal. The procedure record keeps its type, version, engine or model, configuration, input and output digests, and operating limits.

### PD-004 — Authority has three levels

- **Advise:** Recommend a choice. Do not act.
- **Operate:** Make binding choices and act inside one work contract and its limits.
- **Represent:** Act externally on Mike's behalf when the grant allows it. This can include publication, acceptance, closure, spending within a limit, and further delegation.

A level is a ceiling. Every grant still names its work scope, actions, resources, cost, risk, time, and delegation rights.

### PD-005 — Software can make binding judgments

Software can make a binding judgment and execute on Mike's behalf when an explicit grant gives it enough authority.

Mike remains accountable. A judgment does not apply its own effect. A separate executor checks the grant, state revision, preconditions, cancellation state, and idempotency before it acts.

### PD-006 — Representatives can accept and close work

A Represent grant can include authority to accept a result and close its work item.

This capability must be explicit. It is not part of every Represent grant.

### PD-007 — Required failed checks cannot be overridden by software

A software representative cannot accept work while a required check is failed or inconclusive.

It can ask for repair, escalate, reject, cancel, or abandon the work. Mike can make an explicit exception judgment. The exception names the failed criterion, reason, risk, and affected result.

### PD-008 — Work cells can delegate all authority levels

A work cell can give another work cell Advise, Operate, or Represent authority. Every delegation requires a new explicit grant.

Authority never moves automatically. Each child grant names its recipient, work, contract, actions, limits, time, and right to delegate again. The child grant cannot exceed its parent grant.

### PD-009 — Mike sets the maximum delegation depth

Mike's root grant sets the maximum delegation depth. The default is 3.

Each subdelegation reduces the remaining depth by one. A grant at depth 0 cannot delegate authority.

### PD-010 — Revocation cascades

Revoking a grant immediately invalidates every descendant grant.

Affected work becomes blocked. No affected cell can start another judgment, effect, delegation, check, or acceptance. Completed work remains recorded. An outside effect with an unknown result stays unknown until reconciled.

### PD-011 — Parallel work uses child work items

Two cells do not share one execution attempt. A parent creates child work items for parallel work.

Each child has its own contract, assignment, authority, execution attempt, submission, evidence, and return to its parent.

### PD-012 — Due time and expiry are different

A missed due time marks work overdue. It does not stop the work.

Only an explicit expiry policy stops further work. Expiry blocks active attempts and prevents new effects until the work is extended, reassigned, canceled, or closed.

### PD-013 — Work has one of three acceptance policies

- **Automatic:** Required checks pass, and a deterministic policy closes the work.
- **Representative:** Required checks pass, then Mike or a representative with acceptance authority makes the final judgment.
- **Mike only:** Required checks pass, but only Mike can accept the result.

A passing check never changes the selected acceptance policy.

### PD-014 — Mike owns the work-system risk policy

The risk policy sets the minimum acceptance policy for each type of work. A contract can choose a stricter policy. It cannot choose a weaker one.

Only Mike can weaken or change the global risk policy. Software can recommend a change, request an exception, or apply a stricter policy to one contract. It cannot lower its own controls.

### PD-015 — Raw judgment data is policy-controlled evidence

The core stores normalized observations, options, selected option, evidence links, stated basis, uncertainty, risk, authority chain, proposed effects, procedure identity, and input and output digests.

Raw prompts, tool context, and provider responses live in a separate protected artifact store only when policy requires them. The system does not request or store hidden model reasoning.

### PD-016 — Plans are not part of the first core

Planning is a judgment that proposes child work items, effects, checks, and stop conditions. The system creates those real domain objects after it accepts the proposal.

Editable, comparable, reusable plan products can be added later as an extension.

### PD-017 — Judgment has a narrow boundary

Judgment is required when current facts, the accepted contract, explicit policy, and a fixed tie-break rule do not determine one valid next action.

Schema validation, authority checks, state transitions, arithmetic, persistence, objective criteria checks, fixed retry rules, and execution of an accepted step are deterministic work. They are not judgments.

## Open product decisions

These items remain open. Their recommended defaults are not confirmed decisions.

### OPEN-001 — Risk classes and acceptance defaults

Owner: Mike.

Define which actions are routine, high risk, or always reserved to Mike. Define who can classify work when the risk policy has no exact match.

Recommended start: Automatic for internal reversible work, Representative for external reversible work, and Mike only for irreversible, costly, legal, public, or destructive work.

### OPEN-002 — Delegated budget rules

Owner: Mike.

Decide how parent cost and risk limits are divided between child grants.

Recommended start: enforce one shared parent total and allow optional reserved amounts for children. Never copy the full parent budget into every child grant.

### OPEN-003 — Work-cell identity lifetime

Owner: Mike.

Decide whether work-cell principals are durable, temporary per job, or durable with temporary runtime sessions.

Recommended start: durable work-cell principals with temporary runtime sessions.

### OPEN-004 — Recovery after revocation or expiry

Owner: Mike.

Decide when a new grant can resume an existing attempt, when a new attempt is required, whether completed child work must be checked again, and who can ratify earlier work.

### OPEN-005 — Unknown outside effects

Owner: Mike with operations policy.

Define reconciliation, retry, timeout, and compensation rules when an outside action may have happened but did not return a clear result.

### OPEN-006 — Repair and retry limits

Owner: Mike through the risk policy or work contract.

Set default repair and retry limits. Define who may extend a limit and when repeated failure must escalate.

### OPEN-007 — Child-work join rules

Owner: Mike.

Define required and optional child results, whether a parent can continue after a child is canceled or rejected, and which child submissions become parent evidence.

### OPEN-008 — Audit and evidence retention

Owner: Mike, with privacy or legal review when needed.

Set retention, access, deletion, redaction, digest, and tombstone rules for normalized audit records and raw artifacts.

## Related documents

- [Core backlog](work-system-core-backlog.md)
- [Headless pressure findings](headless-pressure-findings.md)
- [Documentation index](README.md)
