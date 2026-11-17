---
name: kata-closeout
description: "End a defined work effort with its work preserved, temporary resources accounted for, and remaining obligations assigned. Use for requested closeout or a closeout dry run; skip ordinary delivery, status, and continued work."
metadata:
  schema: kata.skill/v1
  subject: general
  practice: close
  object: work-effort
  profile: coordination
  authority: destructive
  consumes: "work-request, work-evidence"
  produces: "closeout-report, closed-effort"
---

# Close Out Work

**Outcome:** The user receives the preserved work, its final delivery evidence
when delivery was requested, and the observed state of each selected item.

**Done:** Every required closeout action is verified complete. Retained items
have a reason and an owner, remaining obligations are assigned, and evidence
remains available after cleanup. A blocked required action leaves closeout
incomplete. A requested dry run ends with a proposed action list and evidence
gaps; it does not produce a closed effort.

## Assignment and authority

The required inputs are a defined effort and a closeout request. Work evidence
can come from the selected chat, linked assignments, project records, or current
state. Include only items whose relationship to the effort is supported.

Direct user authority or inherited caller authority supplies the permitted
actions. Record the selected targets, allowed actions, exclusions, and any
unresolved authority before a mutation. A complete request can grant several
actions together. Do not ask for the same authority again.

Commit, push, merge, history changes, worktree removal, local branch deletion,
remote branch deletion, process changes, and chat archival need authority for
the selected action. “Close out” or “clean up this thread” alone permits
inspection and a proposed action list when the intended actions are unclear.
It does not grant these writes. Permanent chat deletion is outside this method.

A dry run changes no files, Git state, processes, or chats. Do not fetch into
local refs during a dry run. Use read-only remote queries or report an unknown.

Use host-neutral capabilities. If the host cannot inspect or change an item,
report the capability gap and next owner. Do not infer that an unavailable
operation succeeded. Do not send messages or stop workers without authority.

## Identify the effort

Identify the exact repositories, chats, branches, worktrees, temporary resources,
and active workers from the selected effort and its linked assignments. Do not
include other work merely because it is recent or uses the same folder.

For each item, record its owner, current state, intended final state, permitted
action, and evidence needed before that action. Mark unknown ownership or state
as unknown. Resolve it before an affected write.

For a dry run, return this inventory, proposed action order, preservation
destinations, retained items, and evidence or authority gaps, then stop.

## Resolve prerequisites

Use the existing delivery method for requested commits, pushes, and merges.
Check providers before consumers when consumers depend on new revisions.
Closeout can proceed without new delivery when publication is not required.

Match verification evidence to the final source and dependency revisions.
Complete required integration or restart checks before removing resources
needed to diagnose a failure. Return missing delivery, verification, or repair
to its existing owner. Jido continues through the checked return when authorized.

## Preserve and remove resources

Confirm that no active worker, process, or other effort still needs a resource.
Recheck ownership, state, and active use immediately before removal. Hold the
action until use ends or an authorized handoff completes.

Before removing a worktree or branch, verify that its required commits,
uncommitted changes, untracked files, ignored data, and result evidence are
preserved at an identified destination or explicitly approved for discard.
A clean checkout alone does not prove that its commits are preserved. A
published branch alone does not prove that its local data is preserved.

Consolidation means preserving accepted work at its selected destination, then
removing temporary checkouts. It does not select a merge or other history change.
Verify preservation even when histories differ after a squash or cherry-pick.
Do not use branch names or apparent age as proof that work can be discarded.

Keep primary checkouts, shared resources, and unrelated work. Retain intentional
exceptions with a reason and an owner. If new unrelated changes appear, preserve
them and reassess the affected action.

Use the host's supported lifecycle operation for managed worktrees. Inspect its
preservation limits, including ignored files, before use. Use normal Git
worktree operations for ordinary linked worktrees. Do not force removal to
bypass unresolved preservation or active-use checks. Verify each operation's
result. Worktree archival and chat archival are separate actions.

## Record and archive

Before removal, preserve required result records outside the checkout scheduled
for removal. Before chat archival, make the final record available in a retained
location or chat. Include delivery destinations and commit identities when
applicable, checks, known limits, removed resources, retained items, and owners
of remaining obligations.

Archive only the selected completed chats when authorized. Verify worker-chat
archival before archiving the coordinating chat last. Do not archive a chat
that owns an unresolved required action unless its responsibility and evidence
have been transferred to an identified owner and archival is authorized.

If the host cannot archive a selected chat, report that required action as
incomplete. Do not substitute permanent deletion. Verify archival through the
host's returned state or a read-back when available.

## Recover from a failed check

Hold affected removal and archival when a required check fails. Gather new
evidence or return the failure to its repair owner within the granted authority,
then repeat the affected check against the repaired state. Do not repeat an
unchanged failure or lower the completion condition.

Continue independent authorized actions when they remain safe. Stop the affected
action when ownership, preservation, authority, capability, or required evidence
cannot be established. Report the exact gap, recovery attempted, and next owner.

## Report

Separate completed actions, deliberate exclusions, and blocked actions. Report
preservation destinations, verification evidence, retained items and their
owners, and observed archival state. Do not claim complete closeout while a
required action remains blocked. Produce `closed-effort` only for completed
execution; a dry run or incomplete execution produces `closeout-report` only.
