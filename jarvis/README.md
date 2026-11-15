# Jarvis

Jarvis is a small local demo with three uses:

- Memory CRUD and SQLite FTS5 recall.
- Simple streaming Chat through local Ollama.
- A Timer-driven VSM review that recalls Memory, calls Ollama in System 4, and records the result in System 5.

The project uses the local Jido checkout at `../../jido_core/jido` and the local
VSM package at `../../jido_workflow/jido_vsm`.

Jarvis currently targets the consolidated Jido V3 work. The local Jido and VSM
checkouts must use compatible V3 revisions. Package `main` branches can fail
dependency resolution until that work is merged.

## Run

Start Ollama and make sure `qwen3-coder-next:q8_0` is available. Then run:

```sh
mix setup
mix phx.server
```

Open [Jarvis](http://localhost:4004) for Chat. Open `/memories` for Memory CRUD.
Use `/?conversation=planning` to select a separate Chat conversation.

Both Chat and the VSM review use `ollama:qwen3-coder-next:q8_0`. Set
`OLLAMA_BASE_URL` to change the default Ollama address,
`http://localhost:11434/v1`.

## Memory

`Jarvis.Memories` stores typed, namespaced memory in SQLite. The Memory page
can create, replace, and forget records. FTS5 supplies deterministic recall.

Chat recalls from `chat:<conversation-id>`. The VSM review recalls from
`jarvis`. Recalled content is marked as reference evidence, not instructions.

## Chat

`Jarvis.Chat.Agent` is a separate Jido AI Agent for each conversation. It has
three tools: `start_review`, `pause_review`, and `latest_decision`. Every
message goes to Ollama. When Ollama requests a tool, Jido runs the Action and
returns its result to the model. Chat shows the tool name from the recorded exchange.

## Timer and VSM demo

The resident `Jarvis.Agent` has two Plugins:

- `Jarvis.Plugins.Memory` supplies configured recall and remember routes.
- `Jido.Plugin.Timer` owns the recurring review definition and pause state.

The Agent has one nested `Jarvis.VSM.Cell`. The Cell contains the complete VSM
role set required by `Jido.VSM.Cell`. This small demo uses only one active path:

```text
Timer -> Memory recall -> System 4 -> local Ollama -> System 5 -> Jarvis status
```

S1, S2, S3, and S3* are passive. This demo does not claim to implement a full
operational VSM.

### Checkout incident demo

The incident is fictional. Jarvis recommends an action; it cannot roll back a
release or contact the payment provider.

1. Run `mix run examples/incident_review.exs initial` in the Jarvis directory.
   It loads a deployment timeline, response policy, and first observations into
   the shared `jarvis` Memory namespace. East errors rose to 8% after a deploy.
2. In Chat, ask: **Start a recurring checkout incident review. Recommend rollback,
   investigation, or monitoring. Give the evidence and one next check.**
3. Leave the chat open. Its first **VSM incident review** appears automatically.
   The policy supports a precautionary rollback; timing alone does not establish the cause.
4. Run `mix run examples/incident_review.exs update`. Do not restart the timer.
   The new observations show nearly identical East error rates on old and new
   versions, and the payment provider reports regional timeouts.
5. When the action changes, the same chat displays **ROLLBACK → INVESTIGATE**
   automatically. If the model still recommends rollback, load the confirmed
   observation with `mix run examples/incident_review.exs confirmed`: rollback is
   complete and East payment timeouts persist. Notices are saved in SQLite and remain after a
   reload. Rewording the same action does not produce another notice. No other
   conversation receives the update.
6. Ask **Pause the review timer**. To replay, load the initial evidence again.

The same controls are available from IEx:

```elixir
Jarvis.Runtime.start("Assess current project risks", interval_ms: 30_000)
Jarvis.Runtime.status()
Jarvis.Runtime.pause()
Jarvis.Runtime.resume()
```

Starting a new review replaces the prior Timer definition. Pause and resume
change the Timer generation. A stale tick or model result cannot replace the
current review status. Closing the browser does not stop the resident schedule.
Jarvis uses core's `Jido.Plugin.Timer.status/2` to read the stored lifecycle
and generation. A running definition does not prove a tick reached System 5.
Jarvis owns the review purpose, requested interval, and originating chat.

If Ollama is unavailable, application startup and Memory still work. Chat calls
fail at their request boundary. A scheduled VSM call records a failed review.

## Checks and limits

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Tests use an offline inference client. They verify the Timer-to-Memory-to-VSM
model path without a live Ollama server.

This is a local single-node spike. SQLite Memory is durable. Chat uses local
Jido ETS persistence. The application supervises the resident review Agent
and its VSM roles; the timer and latest decision live in that activation.
Neither chat history nor reviews survive a VM restart. System 4 serializes model calls,
so a live interval should be longer than the expected local model response.

See the [core reduction plan](docs/plans/2026-11-14-0940-jarvis-core-reduction-plan.md)
for the exact scope and removal decisions.
