# Headless pressure findings

## What was tested

The pressure set has 14 stories. Two stories also appear in the visual player. Twelve stories are headless only.

The final run completed 280 saved work-system runs and 3,170 traced steps. Each story ran 20 times. The result had:

- 170 completed runs;
- 110 stopped runs;
- 0 broken trace rules; and
- 20.3 seconds of total run time on the local test database.

The summary is in `/tmp/jido-work-pressure-280-final.json`. The 280 full traces are in `/tmp/jido-work-traces-280-final`.

## Problems found and fixed

### Database reads became slower as runs were added

The first 280-run test did not finish. It reached the database connection limit after more than two minutes.

Each snapshot read every row from several tables and then filtered the rows in Elixir. This made each new run slower than the run before it.

The store now asks SQLite for only the rows that belong to the current work system and jobs. The same 280-run test now finishes in about 20 seconds.

### Story modules repeated control code

The first two stories each had their own functions for finding the next step and handling a choice.

Stories are now data. A story has a list of steps. A choice is one step that maps a choice name to its next action. This removed repeated control code and made the 12 new stories small.

### Stopped work looked successful

Declined, canceled, and expired jobs first ended with the run status `complete`.

A story step can now end a run with the status `ended`. A job also keeps a specific close status such as `declined`, `canceled`, or `expired`.

## Model gaps

### Cell-to-cell delegation is not fully modeled

The nested-cell story can save work for a smaller specialist cell. It cannot save a true handoff from the parent cell because a delegation can only start from a human actor.

Refinement: let a delegation start from a person or a work cell. Keep the person who owns the full job separate from the actor that sends a smaller job.

### A stopped job has no common closing record

A successful or rejected result has an outcome record tied to a check. A job that ends before it has a result uses only its task status and closing event.

Refinement: add one close record that can represent acceptance, rejection, cancellation, expiry, or decline. A check should be optional when no result exists.

### Beat effects remain in one large runner

Story order is now simple data, but the code that applies each beat is still one large case statement.

Refinement: group beat effects by job setup, handoff, work, check, repair, and close. Do not make one module for every small beat.

## Next pressure layers

The current stories are deterministic. Repeating them tests persistence, trace isolation, and the work rules, but it does not add new input states.

Add these pressure layers next:

1. Seeded input changes for job size, facts, limits, and repair count.
2. Fault injection for database errors, tool timeouts, and checker failures.
3. Concurrent commands that try to change the same run revision.
4. Work queues with cell capacity and waiting jobs.
5. A simulated clock for deadlines, waits, and retry delays.
6. Negative rule tests that change saved records and prove that each trace rule detects the problem.
7. Stream trace files during large runs so the runner does not keep every full trace in memory.

The next implementation should start with seeded input changes, concurrent commands, and negative rule tests. These three changes test the current model without first adding a large scheduling system.
