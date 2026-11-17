# Section 9 Run Evidence

## Deterministic checks

The starting fixture fails the protected acceptance runner. The repaired
fixture passes `normal`, `cancel`, `late_result`, `duplicate_result`, and
`regression`.

The full project check is:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

Result on 2026-11-17: 11 tests passed. The recovery test intentionally stops
the implementer after candidate save and logs that supervised stop.

## Viable Work Cell

Command:

```bash
mix run -e 'IO.inspect(Section9.Demo.run_work_cell(), pretty: true, limit: :infinity)'
```

Observed result:

- eight resident Jido agents;
- two S1 operations: `delivery` and `learning`;
- two coordinated reports and two S3 commands;
- four S3* checks across operational claims and control commands;
- four S4 recommendations observed by S5;
- four repair-team pulses;
- protected evaluation passed; and
- mission and task closed.

The deterministic run uses no model tokens. A pain steering test reaches S3,
S4, and S5. An emergency test stops the effect and leaves the repair task
pending.

## Terra normal run

Trace: `traces/20261117T115926Z-terra-normal-v3.json`

- model: `openai:gpt-6.1-terra`;
- elapsed: 65.599 seconds;
- model calls: 22;
- input tokens: 195,037, including 146,612 cached tokens;
- output tokens: 1,661;
- recorded total cost: $0.076029;
- committed pulses: four; and
- result: mission and task closed.

The lead assigned generation 1. The implementer committed candidate digest
`0dc5810e6d360110ff0378caaf0bd2da45cf9b6244ccd5a9ded113ce60a094ab`.
The evaluator passed the protected checks. The lead then closed the mission.

## Terra interrupted run

Trace: `traces/20261117T120044Z-terra-interrupted.json`

- model: `openai:gpt-6.1-terra`;
- elapsed: 70.062 seconds;
- model calls: 22;
- input tokens: 195,018, including 146,597 cached tokens;
- output tokens: 1,681;
- recorded total cost: $0.076122;
- committed pulses: three; and
- result: mission and task closed.

The implementer saved the candidate and then stopped before it could commit
its actor pulse. The restarted actor reconciled the uncertain candidate. The
evaluator passed it, and the lead closed the mission. The ledger contains both
`candidate_saved_before_report` and `uncertain_candidate_reconciled`. No manual
repair was required.

## Failed model experiments

- LM Studio `lfm3-1.7b` returned a final answer without the required Jido skill
  tool calls. The host rejected the answer. No pulse committed.
- LM Studio `qwen/qwen3.8-27b` failed during structured-output handling before
  the required skill calls. No pulse committed.
- The first Terra structured-output run returned no required skill calls. The
  host rejected it. No pulse committed.
- Terra then loaded the Jido root and command registry but reached the initial
  four-model-call limit. Trace:
  `traces/20261117T115845Z-terra-normal-v2.json`. It used 30,551 total tokens,
  cost $0.014048, and committed no pulse.
- The final configuration allows eight model calls, eight tool rounds, twelve
  tool calls, and 65,536 tool-output bytes. Both complete Terra runs used this
  configuration.

## Interpretation

The runs prove local policy gates, skill loading, persistent work state,
supervised recovery, protected evaluation, and a complete VSM control path.
They do not prove exactly-once external effects, durable VSM memory across a
node restart, outer Work Cell request idempotency, enforced model-cost budgets,
dynamic cell delegation, or that several actors outperform one actor.
