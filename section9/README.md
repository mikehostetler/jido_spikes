# Section 9: Viable Work Cell

Section 9 is a code-first spike for a persistent repair team and its first
fractal control unit: the **Viable Work Cell**.

The cell is a native `Jido.VSM.Cell`. It starts eight Jido agents:

- one cell root;
- S1 `delivery` and `learning` operations; and
- S2 coordination, S3 control, S3* verification, S4 intelligence, and S5
  policy roles.

The cell uses Jido agents, actions, typed signals, directives, topology,
activation, persistence, and the local `jido_vsm` release branch. Section 9
adds a typed work contract, an effect boundary, protected domain checks, a
SQLite work ledger, and the Jido skill package used by its cognitive actors.

## Run the deterministic work cell

```bash
mix deps.get
mix run -e 'IO.inspect(Section9.Demo.run_work_cell(), pretty: true, limit: :infinity)'
```

The deterministic run uses no model tokens. It completes this loop:

```text
purpose -> sense -> decide -> authorize -> act -> verify -> remember
                            \-> escalate
```

The returned map contains evidence for each stage. The effect is not run until
the complete VSM control cycle finishes.

## Simulate a human actor

Run one human-to-cell engagement:

```bash
mix run -e 'IO.inspect(Section9.Demo.run_human_work(), pretty: true, limit: :infinity)'
```

The simulation keeps four concepts separate:

- the task is the prescribed output, quality, target time, resources, and
  authority;
- work is the judgment used under uncertainty;
- control is the cell process that authorizes, stops, or escalates action; and
- evidence is the record that the human uses to accept or reject the output.

The human remains accountable for the result. The human first decides whether
to delegate the task. After the cell returns, the human accepts verified work
or responds to an escalation. Each judgment record contains the observed
situation, available options, decision, and stated basis.

To simulate an emergency response:

```bash
mix run -e 'IO.inspect(Section9.Demo.run_human_work(pressure: :emergency), pretty: true, limit: :infinity)'
```

## Steer the cell

Send a pain signal through S3, S4, and S5:

```bash
mix run -e 'IO.inspect(Section9.ViableWorkCell.steer(:pain, "Slow down"))'
```

Prove that an emergency stops the effect:

```bash
mix run -e 'IO.inspect(Section9.Demo.run_work_cell(pressure: :emergency))'
```

The emergency result is `{:error, {:work_escalated, ...}}`. The repair task
stays pending.

## Run with Terra

Keep `OPENAI_API_KEY` in the ignored `.env` file, then run:

```bash
SECTION9_MODEL=openai:gpt-6.1-terra mix run -e \
  'IO.inspect(Section9.Demo.run_work_cell(model_adapter: Section9.Model.JidoReAct, cost_usd: 1.0), pretty: true, limit: :infinity)'
```

Each cognitive actor must load the Jido root skill and command registry during
its ReAct pulse. This run uses paid API tokens.

## LiveView

```bash
SECTION9_MODEL=openai:gpt-6.1-terra mix phx.server
```

Open [http://localhost:4019](http://localhost:4019). The current LiveView shows
the repair-team ledger, actor state, skill evidence, candidate, evaluation,
and recovery controls. A dedicated Work Cell control panel is deferred to the
next slice.

## Check

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

## Current boundary

- The VSM cell state uses Jido ETS persistence. The repair ledger uses SQLite.
- `delivery` and `learning` use the deterministic default VSM adapter.
- The effect boundary calls one Section 9 work module. It is not a general
  capability registry yet.
- The work contract carries a declared budget, but only the existing mission
  pulse budget is enforced. Cost enforcement is not implemented.
- Actor effects are idempotent in the repair ledger. The outer Work Cell
  request does not yet have a durable idempotency receipt.
- Memory consolidation, recursive child-cell delegation, model routing, and a
  durable human steering inbox are not implemented.
- The cell proves the control path. It does not prove that a swarm is better
  than one agent.
