defmodule JarvisWeb.AliceLive do
  @moduledoc "A LiveView control room for Alice's bounded cognitive cycles."

  use JarvisWeb, :live_view

  alias Jarvis.Alice
  alias Jarvis.Alice.GhostState
  alias JarvisWeb.Markdown

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Alice",
       form: to_form(Alice.default_form(), as: :alice),
       character_prompt: Alice.character_prompt(),
       character_version: Alice.character().version,
       run: nil,
       operation: :idle,
       turn_count: 0,
       active_turn: nil,
       active_turn_token: nil,
       error: nil
     )
     |> stream(:turns, [])}
  end

  @impl true
  def handle_event("start", %{"alice" => params}, socket) do
    case validate(params) do
      :ok ->
        run = Alice.new_run(params)

        socket =
          socket
          |> assign(
            form: to_form(params, as: :alice),
            character_prompt: run.character_prompt,
            character_version: run.character.version,
            run: run,
            operation: if(run.mode == :automatic, do: :running, else: :ready),
            turn_count: 0,
            active_turn: nil,
            active_turn_token: nil,
            error: nil
          )
          |> stream(:turns, [], reset: true)

        if run.mode == :automatic, do: dispatch_turn(socket), else: {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("next", _params, %{assigns: %{run: nil}} = socket),
    do: {:noreply, assign(socket, error: "Start an Alice run first.")}

  def handle_event("next", _params, %{assigns: %{operation: :running}} = socket),
    do: {:noreply, socket}

  def handle_event("next", _params, socket), do: dispatch_turn(socket)

  def handle_event("stop", _params, socket) do
    operation = if socket.assigns.operation == :running, do: :stopping, else: :stopped
    {:noreply, assign(socket, operation: operation)}
  end

  @impl true
  def handle_info({:alice_turn_result, token, result}, socket) do
    case {socket.assigns.run, token} do
      {%{} = run, {run_id, expected_turn}}
      when run_id == run.id and expected_turn == run.turn + 1 ->
        apply_turn_result(socket, result)

      _stale ->
        {:noreply, socket}
    end
  end

  def handle_info({:alice_stream, token, %Jido.Signal{} = signal}, socket) do
    if token == socket.assigns.active_turn_token do
      {:noreply, apply_stream_signal(socket, signal)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:dispatch_alice_effect, run_id, effect}, socket) do
    case socket.assigns.run do
      %{id: ^run_id} = run ->
        if Map.has_key?(run.effect_receipts, effect.id) do
          {:noreply, socket}
        else
          receipt = Alice.dispatch_effect(effect, run)

          run = %{
            run
            | pending_effects: Enum.reject(run.pending_effects, &(&1.id == effect.id)),
              effect_receipts: Map.put(run.effect_receipts, effect.id, receipt)
          }

          {:noreply, assign(socket, run: run)}
        end

      _other ->
        {:noreply, socket}
    end
  end

  def handle_info(:continue_alice, %{assigns: %{operation: :running}} = socket),
    do: dispatch_turn(socket)

  def handle_info(:continue_alice, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="alice-shell">
      <header class="jarvis-header">
        <div>
          <p class="eyebrow">Section 9 actor · bounded ghost · replaceable shell</p>
          <h1>Alice</h1>
          <p class="subtitle">Watch the Major complete one bounded cognitive cycle at a time.</p>
        </div>
        <div class="header-actions">
          <.link navigate={~p"/"} class="nav-link">Jarvis</.link>
          <.link navigate={~p"/memories"} class="nav-link">Memories</.link>
          <div class="model-chip"><span class="status-dot"></span>{Alice.model()}</div>
        </div>
      </header>

      <section class="alice-character" aria-labelledby="alice-character-title">
        <div class="section-heading">
          <div>
            <p class="eyebrow">Stable identity kernel · Jido.Character</p>
            <h2 id="alice-character-title">Who Alice is</h2>
          </div>
          <span id="alice-character-version" class="alice-status">
            version {@character_version}
          </span>
        </div>
        <details open id="alice-character-kernel">
          <summary>Exact rendered character prompt</summary>
          <pre id="alice-character-prompt">{@character_prompt}</pre>
        </details>
        <p class="alice-namespace">
          This kernel stays fixed while ghost-state, episodic memory, and run directives change.
        </p>
      </section>

      <section class="alice-config" aria-labelledby="alice-config-title">
        <div class="section-heading">
          <div>
            <p class="eyebrow">Initial context</p>
            <h2 id="alice-config-title">Set Alice in motion</h2>
          </div>
          <span id="alice-operation" class="alice-status">{@operation}</span>
        </div>

        <.form for={@form} id="alice-form" phx-submit="start">
          <.input
            field={@form[:run_directive]}
            type="textarea"
            label="Run directive"
            rows="5"
            required
          />
          <.input
            field={@form[:thought]}
            type="textarea"
            label="Initial thought"
            rows="5"
            placeholder="What should Alice think through?"
            required
          />
          <div class="alice-options">
            <.input
              field={@form[:mode]}
              type="select"
              label="Run mode"
              options={[{"Step", "step"}, {"Automatic", "automatic"}]}
            />
            <.input
              field={@form[:turn_limit]}
              type="number"
              label="Cycle limit"
              min="1"
              max="100"
              required
            />
          </div>
          <div class="alice-controls">
            <button id="alice-start" type="submit" class="primary-button">Start new run</button>
            <button
              :if={@run && @run.mode == :step && @turn_count < @run.turn_limit}
              id="alice-next"
              type="button"
              phx-click="next"
              class="text-button"
              disabled={@operation == :running}
            >
              Next cycle
            </button>
            <button
              :if={@operation in [:running, :stopping]}
              id="alice-stop"
              type="button"
              phx-click="stop"
              class="text-button"
            >
              Stop after this cycle
            </button>
          </div>
        </.form>
        <p :if={@error} id="alice-error" class="chat-error">{@error}</p>
      </section>

      <section :if={@run} class="alice-current" aria-labelledby="current-context-title">
        <div class="section-heading">
          <div>
            <p class="eyebrow">Live ghost-state</p>
            <h2 id="current-context-title">
              {if @turn_count >= @run.turn_limit,
                do: "Final ghost-state",
                else: "Ghost-state for cycle #{@turn_count + 1}"}
            </h2>
          </div>
          <span id="alice-progress" class="alice-status">
            {@turn_count} / {@run.turn_limit} · {@run.mode}
          </span>
        </div>
        <pre id="alice-current-context">{GhostState.render(@run.ghost_state)}</pre>
        <p class="alice-namespace">
          Memory namespace <code>{@run.memory_namespace}</code>
          · pending effects {length(@run.pending_effects)} · effect receipts {map_size(
            @run.effect_receipts
          )}
        </p>
      </section>

      <section :if={@run} class="alice-turns" aria-labelledby="alice-turns-title">
        <div class="section-heading">
          <div>
            <p class="eyebrow">Context audit</p>
            <h2 id="alice-turns-title">Cognitive cycle history</h2>
          </div>
        </div>
        <div id="alice-turn-list" phx-update="stream" class="alice-turn-list">
          <p id="alice-turns-empty" class="memory-empty hidden only:block">
            No cycles yet. Use Next cycle or automatic mode.
          </p>
          <article :for={{dom_id, turn} <- @streams.turns} id={dom_id} class="alice-turn-card">
            <header>
              <div>
                <span class="alice-turn-number">Cycle {turn.turn}</span>
                <span>{turn.model}</span>
              </div>
              <span class={"alice-turn-state alice-turn-state-#{turn.status}"}>
                {turn.status} · call {turn.model_call} · {turn.stream_events} chunks
              </span>
            </header>
            <div class="alice-context-grid">
              <div>
                <h3>Ghost-state in</h3>
                <pre id={"alice-context-in-#{turn.turn}"}>{turn.input_context}</pre>
              </div>
              <div>
                <h3>Ghost-state out</h3>
                <pre id={"alice-context-out-#{turn.turn}"}>{turn.next_context}</pre>
              </div>
            </div>
            <details>
              <summary>Exact model input</summary>
              <pre id={"alice-model-input-#{turn.turn}"}>{turn.model_input}</pre>
            </details>
            <details open>
              <summary>Alice output · live tokens</summary>
              <div :if={turn.status == :complete} class="message-body markdown-body">
                {raw(Markdown.render(turn.output))}
              </div>
              <pre
                :if={turn.status != :complete}
                id={"alice-stream-output-#{turn.turn}"}
                class="alice-live-stream"
              >{turn.stream_text}</pre>
            </details>
            <details :if={turn.thinking_text != ""} open>
              <summary>Private reasoning stream</summary>
              <pre
                id={"alice-thinking-output-#{turn.turn}"}
                class="alice-live-stream alice-thinking-stream"
              >{turn.thinking_text}</pre>
            </details>
            <footer>
              {String.length(turn.model_input)} input characters · strategy {turn.strategy} · recalled memory IDs {inspect_ids(
                turn.recalled_memory_ids
              )} · tools {tool_policy_label(turn)} · staged effects {length(turn.staged_effects)} · stored memory IDs {inspect_ids(
                turn.stored_memory_ids
              )}
            </footer>
          </article>
        </div>
      </section>
    </div>
    """
  end

  defp dispatch_turn(%{assigns: %{run: run}} = socket) do
    cond do
      run.turn >= run.turn_limit ->
        {:noreply, assign(socket, operation: :complete)}

      socket.assigns.operation == :stopping ->
        {:noreply, assign(socket, operation: :stopped)}

      true ->
        caller = self()
        token = {run.id, run.turn + 1}
        prepared = Alice.prepare_turn(run)

        socket =
          socket
          |> assign(
            operation: :running,
            error: nil,
            active_turn: prepared,
            active_turn_token: token
          )
          |> stream_insert(:turns, prepared)

        case Task.Supervisor.start_child(Jarvis.TaskSupervisor, fn ->
               result =
                 Alice.run_turn(run,
                   prepared: prepared,
                   stream_to: caller,
                   stream_token: token
                 )

               send(caller, {:alice_turn_result, token, result})
             end) do
          {:ok, _pid} ->
            {:noreply, socket}

          {:error, reason} ->
            failed = %{prepared | status: :failed}

            {:noreply,
             socket
             |> assign(operation: :failed, error: inspect(reason), active_turn: failed)
             |> stream_insert(:turns, failed)}
        end
    end
  end

  defp apply_turn_result(socket, {:ok, turn}) do
    turn = preserve_stream_state(turn, socket.assigns.active_turn)

    pending_effects =
      (socket.assigns.run.pending_effects ++ turn.staged_effects)
      |> Enum.uniq_by(& &1.id)

    run = %{
      socket.assigns.run
      | turn: turn.turn,
        ghost_state: turn.next_ghost_state,
        pending_effects: pending_effects
    }

    operation =
      cond do
        socket.assigns.operation == :stopping -> :stopped
        run.turn >= run.turn_limit -> :complete
        turn.next_wake == :stop -> :complete
        run.mode == :automatic -> :running
        turn.next_wake == :wait -> :waiting
        true -> :ready
      end

    socket =
      socket
      |> assign(
        run: run,
        operation: operation,
        turn_count: turn.turn,
        active_turn: nil,
        active_turn_token: nil,
        error: nil
      )
      |> stream_insert(:turns, turn)

    Enum.each(turn.staged_effects, fn effect ->
      send(self(), {:dispatch_alice_effect, run.id, effect})
    end)

    if operation == :running do
      send(self(), :continue_alice)
    end

    {:noreply, socket}
  end

  defp apply_turn_result(socket, {:error, reason}) do
    socket =
      case socket.assigns.active_turn do
        nil -> socket
        turn -> stream_insert(socket, :turns, %{turn | status: :failed})
      end

    {:noreply,
     assign(socket,
       operation: :failed,
       active_turn: nil,
       active_turn_token: nil,
       error: inspect(reason)
     )}
  end

  defp apply_stream_signal(socket, %Jido.Signal{type: type, data: data}) do
    turn = socket.assigns.active_turn

    updated =
      case type do
        "jido.ai.model.stream.started" ->
          call = Map.get(data, :model_call, turn.model_call)
          prefix = if call > 1, do: "\n\n— model call #{call} —\n\n", else: ""

          %{
            turn
            | status: :streaming,
              model_call: call,
              stream_text: turn.stream_text <> prefix
          }

        "jido.ai.model.stream.chunk" ->
          chunk = Map.get(data, :chunk, %{})
          text = Map.get(chunk, :text) || ""

          case Map.get(chunk, :type) do
            :thinking ->
              %{
                turn
                | thinking_text: turn.thinking_text <> text,
                  stream_events: turn.stream_events + 1
              }

            :content ->
              %{
                turn
                | stream_text: turn.stream_text <> text,
                  stream_events: turn.stream_events + 1
              }

            _other ->
              %{turn | stream_events: turn.stream_events + 1}
          end

        "jido.ai.model.stream.completed" ->
          %{turn | status: :transforming}

        "jido.ai.model.stream.failed" ->
          %{turn | status: :failed}

        _other ->
          turn
      end

    socket
    |> assign(active_turn: updated)
    |> stream_insert(:turns, updated)
  end

  defp preserve_stream_state(turn, nil), do: turn

  defp preserve_stream_state(turn, streamed) do
    Map.merge(turn, Map.take(streamed, [:model_call, :stream_events, :thinking_text]))
  end

  defp tool_policy_label(%{tool_policy: %{requirement: :disabled}}), do: "disabled"
  defp tool_policy_label(%{visible_tools: tools}), do: Enum.join(tools, ", ")

  defp inspect_ids(ids), do: inspect(ids, charlists: :as_lists)

  defp validate(params) do
    cond do
      String.trim(Map.get(params, "run_directive", "")) == "" ->
        {:error, "Enter a run directive."}

      String.trim(Map.get(params, "thought", "")) == "" ->
        {:error, "Enter an initial thought."}

      true ->
        :ok
    end
  end
end
