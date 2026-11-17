defmodule Section9Web.DashboardLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Section9.PubSub, "section9:ledger")
      Phoenix.PubSub.subscribe(Section9.PubSub, "section9:stream")
    end

    {:ok,
     assign(socket,
       snapshot: Section9.Ledger.snapshot(),
       stream: %{},
       current_input: nil,
       running: false,
       dev_controls: Application.get_env(:section9, :dev_controls, false),
       notice: "Ready."
     )}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    %{baseline: baseline} = Section9.Demo.reset()

    {:noreply,
     refresh(
       socket,
       "Reset complete. Baseline status=#{baseline.status}; pass=#{baseline.passed}."
     )}
  end

  def handle_event("step", %{"role" => role}, socket) do
    run_async(socket, fn -> Section9.Team.step(String.to_existing_atom(role)) end)
  end

  def handle_event("auto_fake", _params, socket) do
    run_async(socket, fn -> Section9.Team.run_auto(model_adapter: Section9.Model.Fake) end)
  end

  def handle_event("auto_local", _params, socket) do
    run_async(socket, fn -> Section9.Team.run_auto(model_adapter: Section9.Model.JidoReAct) end)
  end

  def handle_event("interrupt", _params, socket) do
    :ok = Section9.Demo.interrupt_implementer()

    {:noreply,
     assign(socket, notice: "The next implementer pulse will stop after candidate save.")}
  end

  @impl true
  def handle_info(:ledger_changed, socket), do: {:noreply, refresh(socket, socket.assigns.notice)}

  def handle_info({:pulse_started, role, id, input}, socket) do
    {:noreply,
     assign(socket,
       current_input: %{role: role, id: id, text: input},
       stream: Map.put(socket.assigns.stream, role, "")
     )}
  end

  def handle_info({:pulse_stream, role, _id, text}, socket) do
    {:noreply,
     update(socket, :stream, &Map.update(&1, role, text, fn current -> current <> text end))}
  end

  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket |> assign(running: false) |> refresh("Run result: #{inspect(result)}")}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply,
     socket |> assign(running: false) |> refresh("Run process stopped: #{inspect(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p class="eyebrow">Jido + OTP recovery spike</p>
      <h1>Section 9 · Persistent Repair Team</h1>
      <p class="muted">Three stable actor identities coordinate through one durable SQLite ledger. Visible state is evidence, not hidden model reasoning.</p>

      <div class="bar">
        <section class="card"><span class="muted">Mission</span><div class="metric status">{@snapshot.mission.status}</div><div>{@snapshot.mission.id}</div></section>
        <section class="card"><span class="muted">Task</span><div class="metric">{@snapshot.task.status}</div><div>{@snapshot.task.owner || "unowned"}</div></section>
        <section class="card"><span class="muted">Claim generation</span><div class="metric gen">{@snapshot.task.claim_generation}</div><div>lease: {@snapshot.task.lease_until || "none"}</div></section>
        <section class="card"><span class="muted">Mission budget</span><div class="metric">{@snapshot.mission.pulses_used}/{@snapshot.mission.pulse_budget}</div><div>committed pulses</div></section>
      </div>

      <div class="controls">
        <button phx-click="reset">Reset fixture</button>
        <button :for={role <- ~w(lead implementer evaluator)} phx-click="step" phx-value-role={role}>Step {role}</button>
        <button phx-click="auto_fake">Automatic · fake</button>
        <button phx-click="auto_local">Automatic · LM Studio</button>
        <button :if={@dev_controls} class="danger" phx-click="interrupt">Interrupt next implementer</button>
      </div>
      <p class="muted">{@notice} <%= if @running, do: "A pulse is running…" %></p>

      <div class="roles">
        <section :for={actor <- @snapshot.actors} class="card">
          <div class="role-title"><h2>{actor.role}</h2><span class="revision">rev {actor.revision}</span></div>
          <pre>{Jason.encode!(actor.state, pretty: true)}</pre>
          <div class="stream"><strong>provisional stream</strong><br />{Map.get(@stream, String.to_existing_atom(actor.role), "idle")}</div>
        </section>
      </div>

      <div class="grid">
        <div>
          <section class="card">
            <h2>Candidate diff</h2>
            <pre>{if @snapshot.candidate, do: @snapshot.candidate.diff, else: "No candidate committed."}</pre>
          </section>
          <section class="card" style="margin-top:14px">
            <h2>Evaluation evidence</h2>
            <pre>{if @snapshot.evaluation, do: Jason.encode!(@snapshot.evaluation.evidence, pretty: true), else: "No evaluation committed."}</pre>
          </section>
          <section class="card" style="margin-top:14px">
            <h2>Rendered input and committed state changes</h2>
            <details :if={@current_input}><summary>Current in-progress input · {@current_input.role}</summary><pre>{@current_input.text}</pre></details>
            <details :for={pulse <- Enum.reverse(@snapshot.pulses)}>
              <summary>#{pulse.number} · {pulse.role} · {pulse.status}</summary>
              <h3>Model input</h3><pre>{pulse.input.exact}</pre>
              <h3>State before</h3><pre>{Jason.encode!(pulse.state_before, pretty: true)}</pre>
              <h3>State after</h3><pre>{Jason.encode!(pulse.state_after, pretty: true)}</pre>
              <h3>Committed result</h3><pre>{Jason.encode!(pulse.output, pretty: true)}</pre>
            </details>
          </section>
        </div>

        <section class="card timeline">
          <h2>Shared ledger timeline</h2>
          <div :for={event <- Enum.reverse(@snapshot.events)} class="event">
            <strong>#{event.seq} · {event.type}</strong>
            <div class="muted">{event.created_at}</div>
            <pre>{Jason.encode!(event.data, pretty: true)}</pre>
          </div>
        </section>
      </div>
    </main>
    """
  end

  defp run_async(socket, fun) do
    task = Task.async(fun)
    {:noreply, assign(socket, running: true, notice: "Run started. Task=#{inspect(task.ref)}")}
  end

  defp refresh(socket, notice) do
    assign(socket, snapshot: Section9.Ledger.snapshot(), notice: notice)
  end
end
