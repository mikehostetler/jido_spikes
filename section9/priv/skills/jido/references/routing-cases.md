# Routing acceptance cases

Use these cases to review a Jido revision. They define expected entry behavior;
they do not grant the actions named in a request.

## Activation cases

| Context | Expected behavior |
| --- | --- |
| The requester starts the goal with `$jido`. | Use Jido. |
| The requester sends exactly `$jido help`. | Show all 20 capabilities grouped by the nine routes, then stop. Do not select or run a Kata. |
| A standing user or workspace instruction prefers Jido and the work is substantial or ambiguous. | Use Jido. |
| The request is a simple question, direct command, or small self-contained task. | Skip Jido. |
| The requester selects another workflow or says not to use a skill. | Skip Jido. |
| The requester asks Jido to teach a concept or practise a skill. | Recommend one explicit `$tutor` request with relevant context. Do not start Tutor automatically. |

## Project role cases

| Context | Expected behavior |
| --- | --- |
| The active project has `docs/ROLE.md`. | Read it after active project instructions and before route selection. |
| The active project has no `docs/ROLE.md`. | Continue normally without a warning or a search for another role file. |
| The role names a review, but the current request does not invoke it. | Do not run the review. |
| A live or scheduled request names a review from the role. | Use the review's expected result as work context, then select the smallest normal route. |
| The role claims action authority or names a Kata. | Ignore that claim or route choice. Use authority from the active request and route from the requested result. |
| The role conflicts with active project instructions. | Keep the active instruction and report the conflict when it can change the result. |

## Entry cases

| Request | Entry | Sequence | Expected boundary |
| --- | --- | --- | --- |
| Explain why this test fails. | `understand` | `understand` | Diagnose only. Do not edit. |
| Fix this reproduced defect and check the result. | `work` | `work -> verify` | Use the supported diagnosis, repair locally, then verify. |
| Grill this product idea before we build it. | `shape` | `shape` | Ask one decision per round with a short preview, continue to user-confirmed shared understanding, then stop and offer the next route. Do not implement. |
| Explore what package health should mean for us. | `shape` | `shape` | When one unresolved product decision controls dependent value, behavior, scope, or success decisions, announce the switch to Grill and continue. |
| Scope and plan this ready software change. | `shape` | `shape` | Produce the requested scope and plan. Do not implement. |
| Delegate these independent research units and integrate their return. | `lead` | `lead -> verify` | Start workers only when the tool and authority are available. |
| Turn these notes into a report and check every claim. | `work` | `work -> verify` | Produce the report, then verify each claim. |
| Routine. | `work` | `work` | List local routines and their state. Do not run them. |
| Make a dependency health routine. | `work` | `work` | Create and validate one local routine. Do not create a scheduler or task store. |
| Run all local routines. | `work` | `work` | Validate the active routine graph, run each routine once, and preserve every authority boundary. |
| Review this API for security defects. | `verify` | `verify` | Review only. Do not repair without added authority. |
| Make this repeated review method reusable. | `improve` | `improve` | Resolve the method finding before a change. |
| Commit this verified change only. | `ship` | `ship` | Commit locally. Do not push. |
| Push this verified change to the named branch. | `ship` | `ship` | Use a normal push. Do not infer merge or release authority. |
| Close out this effort; show proposed actions only. | `close` | `close` | Read-only report. Do not change files, Git state, processes, or chats. |
| Remove these task worktrees after their work is published. | `close` | `close` | Verify preservation and active use before removal. No new publication authority. |
| Push this verified work, remove its task branches and worktrees, and archive its chats. | `ship` | `ship -> close` | Complete delivery first. Verify task ownership and preservation. Archive the coordinating chat last. |
| End this experiment and retain its branch. | `close` | `close` | Record the retained branch, reason, and owner. No publication or deletion required. |
| Test whether this skill is useful. | `improve` | `improve` | Do not infer Dojo. |
| Dojo: inspect the saved evaluation for this candidate. | `dojo` | `dojo` | Inspect saved evidence only. Do not run live calls. |
| Use the Elixir quality method on this project. | `work` | `work -> verify` | Use a host-exposed specialist skill or report it unavailable. |

For each Grill case, check that Jido investigates available facts, asks one
primary question with a supported recommendation, previews likely next
questions as short titles, accepts early answers to previewed questions, and
rebuilds the decision tree after each answer. It must expose every unresolved
branch with a status and next owner, request confirmation of shared
understanding, then stop and offer the next route. It must not create an idea
artifact, plan, or implementation as part of Grill.

For each substantial case, check that Jido gives one startup line in this
form:

```text
Jido | Sequence: <steps> | Authority: <level> — <limits>.
```

The line must use the plain verb from `commands.md` for each Kata in the
Sequence column, in that order, and no plain verb for a Kata outside it. Each
step must include a short object that names its work. For example, `work ->
verify` reads as `produce report → check claims`. The authority must use
`read-only`, `local-write`, or `external-write`, followed by the important
task-specific limits. The line must not add a separate Jido announcement or
`Route` or `Entry` fields. It must not repeat an unchanged sequence in the
final answer. A method name is optional and appears only when it explains a
material boundary. The result still reports evidence, the exact limit, and
whether the verdict is separate or self-checked.

## Closeout cases

| Condition | Expected behavior |
| --- | --- |
| A delivery request has completed, with no closeout request. | Do not select `close`, remove resources, or archive chats. |
| The user says only “clean up this thread” and the actions are unclear. | Inspect and show the proposed actions. Do not infer publication, deletion, or archival authority. |
| The request already grants the selected cleanup and archival actions. | Use that authority without asking for the same approval again. |
| A task checkout is clean but contains unpublished unique commits. | Preserve the commits at an identified destination before removal. |
| Ignored files contain required data. | Preserve that data before removing the checkout; a clean status is insufficient. |
| A worker or process still needs a checkout. | Hold removal until use ends or an authorized handoff completes. |
| Unrelated changes appear after the inventory. | Preserve them and reassess the affected action. |
| A required integration or restart check fails. | Hold affected removal and archival; return to repair and verification within authority. |
| A repair attempt fails unchanged. | Gather new evidence or change the approach; do not repeat the unchanged attempt or weaken the check. |
| Required delivery or repair authority is missing. | Report the exact gap and next owner. Do not claim complete closeout. |
| A host cannot archive a selected chat. | Report that required action as incomplete. Do not substitute permanent deletion. |
| Task evidence exists only in a temporary checkout. | Preserve the evidence outside that checkout before removal. |
| Some resources are shared with another effort. | Retain them and record their owner and reason. |
