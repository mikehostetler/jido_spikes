defmodule JidoWorkSystemWeb.SimulationLive do
  use JidoWorkSystemWeb, :live_view

  alias JidoWorkSystem.Simulation

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Mike's Work Story",
        scenarios: Simulation.scenarios(),
        state: nil,
        mode: :paused,
        error: nil,
        missing?: false
      )

    {:ok, load_from_params(socket, params)}
  end

  @impl true
  def handle_event("start", %{"scenario" => scenario_key}, socket) do
    case Simulation.start_scenario(scenario_key) do
      {:ok, state} ->
        {:noreply, push_navigate(socket, to: ~p"/runs/#{state.run.id}")}

      {:error, :unknown_scenario} ->
        {:noreply, assign(socket, :error, "That story is not available.")}
    end
  end

  def handle_event("restart", _params, %{assigns: %{state: state}} = socket) do
    case Simulation.start_scenario(state.run.scenario_key) do
      {:ok, next} -> {:noreply, push_navigate(socket, to: ~p"/runs/#{next.run.id}")}
      {:error, reason} -> {:noreply, show_error(socket, reason)}
    end
  end

  def handle_event("step", _params, socket) do
    {:noreply, advance(assign(socket, :mode, :paused))}
  end

  def handle_event("play", _params, socket) do
    socket = assign(socket, :mode, :playing)

    if playable?(socket.assigns.state) do
      {:noreply, advance(socket)}
    else
      {:noreply, assign(socket, :mode, :paused)}
    end
  end

  def handle_event("pause", _params, socket) do
    {:noreply, assign(socket, :mode, :paused)}
  end

  def handle_event("choose", %{"choice" => choice}, %{assigns: %{state: state}} = socket) do
    case Simulation.choose(state.run.id, state.run.revision, choice) do
      {:ok, next} ->
        {:noreply, socket |> assign_state(next) |> push_projection()}

      {:error, reason} ->
        {:noreply, show_error(socket, reason)}
    end
  end

  def handle_event("scene_ready", _params, %{assigns: %{state: nil}} = socket) do
    {:reply, %{status: "no_run"}, socket}
  end

  def handle_event("scene_ready", _params, %{assigns: %{state: state}} = socket) do
    {:reply, state.projection, socket}
  end

  def handle_event(
        "animation_complete",
        %{"run_id" => run_id, "revision" => revision},
        %{assigns: %{state: state, mode: :playing}} = socket
      ) do
    if state.run.id == run_id and state.run.revision == revision and playable?(state) do
      {:noreply, advance(socket)}
    else
      {:noreply, maybe_pause(socket)}
    end
  end

  def handle_event("animation_complete", _params, socket), do: {:noreply, socket}

  def handle_event("stage_failed", _params, socket) do
    {:noreply,
     socket
     |> assign(:mode, :paused)
     |> assign(
       :error,
       "The picture could not start. You can still use Step or open the full details."
     )}
  end

  defp load_from_params(socket, %{"id" => run_id}) do
    case Simulation.get_run(run_id) do
      {:ok, state} -> assign_state(socket, state)
      {:error, :not_found} -> assign(socket, :missing?, true)
    end
  end

  defp load_from_params(socket, _params), do: socket

  defp advance(%{assigns: %{state: nil}} = socket), do: socket

  defp advance(%{assigns: %{state: state}} = socket) do
    case Simulation.step(state.run.id, state.run.revision) do
      {:ok, next} ->
        socket
        |> assign_state(next)
        |> push_projection()
        |> maybe_pause()

      {:error, reason} ->
        socket
        |> assign(:mode, :paused)
        |> show_error(reason)
    end
  end

  defp assign_state(socket, state) do
    assign(socket,
      state: state,
      page_title: state.projection.scenario.title,
      missing?: false,
      error: nil
    )
  end

  defp push_projection(%{assigns: %{state: state}} = socket) do
    push_event(socket, "scene:sync", state.projection)
  end

  defp maybe_pause(%{assigns: %{state: state}} = socket) do
    if playable?(state), do: socket, else: assign(socket, :mode, :paused)
  end

  defp playable?(%{run: %{status: status}}), do: status in ["ready", "running"]
  defp playable?(_state), do: false

  defp show_error(socket, :stale_revision),
    do: assign(socket, :error, "The story changed. Reload this page and try again.")

  defp show_error(socket, :choice_required),
    do: assign(socket, :error, "Mike must choose what to do next.")

  defp show_error(socket, :complete),
    do: assign(socket, :error, "This story is done.")

  defp show_error(socket, _reason),
    do:
      assign(socket, :error, "The story could not move to the next step. Open the full details.")

  defp status_label("ready"), do: "Ready"
  defp status_label("running"), do: "Work in progress"
  defp status_label("waiting_for_choice"), do: "Mike must choose"
  defp status_label("complete"), do: "Done"
  defp status_label("ended"), do: "Stopped"
  defp status_label(status), do: String.replace(status, "_", " ")

  defp beat_label("ready"), do: "Ready to start"
  defp beat_label("define_task"), do: "Mike explains the job"
  defp beat_label("delegate_task"), do: "Mike gives the job to the cell"
  defp beat_label("accept_delegation"), do: "The cell takes the job"
  defp beat_label("plan_work"), do: "The cell makes a plan"
  defp beat_label("check_authority"), do: "The cell checks the rules"
  defp beat_label("select_draft"), do: "The cell chooses a first draft"
  defp beat_label("write_draft"), do: "The cell writes the note"
  defp beat_label("record_complete_evidence"), do: "The cell sends the note to the checker"
  defp beat_label("record_incomplete_evidence"), do: "The cell sends the note to the checker"
  defp beat_label("verify_pass"), do: "The checker says the note is ready"
  defp beat_label("verify_fail"), do: "The checker finds a missing part"
  defp beat_label("request_revision"), do: "Mike asks the cell to fix it"
  defp beat_label("rework_judgment"), do: "The cell plans the fix"
  defp beat_label("revise_draft"), do: "The cell fixes the note"
  defp beat_label("record_revised_evidence"), do: "The cell sends the fixed note"
  defp beat_label("verify_revised"), do: "The checker checks the note again"
  defp beat_label("accept_outcome"), do: "Mike says the job is done"
  defp beat_label("accept_after_rework"), do: "Mike says the job is done"
  defp beat_label("end_run"), do: "Mike stops the job"
  defp beat_label(beat), do: String.replace(beat, "_", " ")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= cond do %>
        <% @missing? -> %>
          <section id="run-not-found" class="panel text-center">
            <p class="eyebrow">Work story</p>
            <h1 class="section-title">This story does not exist.</h1>
            <.link
              navigate={~p"/"}
              class="mt-4 inline-flex rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-content"
            >
              Choose a story
            </.link>
          </section>
        <% @state == nil -> %>
          <section class="overflow-hidden rounded-[2rem] bg-[radial-gradient(circle_at_top_left,_#315a70,_#16232d_55%,_#111820)] px-6 py-12 text-white shadow-xl sm:px-10 lg:px-14">
            <div class="max-w-3xl">
              <p class="text-xs font-semibold uppercase tracking-[0.28em] text-cyan-200">
                A Jido work story
              </p>
              <h1 class="mt-4 text-4xl font-semibold tracking-tight sm:text-6xl">
                Watch Mike get work done.
              </h1>
              <p class="mt-5 max-w-2xl text-base leading-7 text-slate-200 sm:text-lg">
                Mike needs a note with three parts: what changed, what could go wrong, and what people need to do. Mike gives the job to a work cell. Step through the story to see what happens.
              </p>
            </div>
          </section>

          <section id="scenario-catalog" class="grid gap-5 lg:grid-cols-2">
            <article
              :for={scenario <- @scenarios}
              id={"scenario-#{scenario.key}"}
              class="group relative overflow-hidden rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm transition duration-300 hover:-translate-y-1 hover:shadow-xl"
            >
              <div class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-cyan-400 via-primary to-violet-500">
              </div>
              <p class="eyebrow">Story</p>
              <h2 class="mt-2 text-2xl font-semibold tracking-tight">{scenario.title}</h2>
              <p class="mt-3 text-sm leading-6 text-base-content/70">{scenario.summary}</p>
              <div class="mt-5 rounded-xl bg-base-200 p-4">
                <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                  What you will see
                </p>
                <p class="mt-2 text-sm">{scenario.learning_point}</p>
              </div>
              <button
                id={"start-#{scenario.key}"}
                phx-click="start"
                phx-value-scenario={scenario.key}
                class="mt-6 inline-flex items-center gap-2 rounded-xl bg-neutral px-4 py-3 text-sm font-semibold text-neutral-content shadow-sm transition group-hover:bg-primary group-hover:text-primary-content"
              >
                Start story <.icon name="hero-arrow-right-mini" class="size-4" />
              </button>
            </article>
          </section>
        <% true -> %>
          <% projection = @state.projection %>
          <% run = @state.run %>

          <div id="simulation-player" class="space-y-5">
            <section class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <.link
                    navigate={~p"/"}
                    class="text-xs font-semibold uppercase tracking-[0.2em] text-primary hover:underline"
                  >Stories</.link>
                  <span class="text-base-content/30">/</span>
                  <span
                    id="run-status"
                    class="rounded-full bg-base-300 px-3 py-1 text-xs font-semibold uppercase tracking-wide"
                  >{status_label(run.status)}</span>
                </div>
                <h1 class="mt-3 text-3xl font-semibold tracking-tight">
                  {projection.scenario.title}
                </h1>
                <p class="mt-2 max-w-3xl text-sm text-base-content/65">
                  {projection.scenario.learning_point}
                </p>
              </div>
              <div class="flex gap-2">
                <.link
                  id="debug-link"
                  navigate={~p"/runs/#{run.id}/debug"}
                  class="rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs font-semibold transition hover:border-primary hover:text-primary"
                >
                  See all details
                </.link>
                <button
                  id="restart"
                  phx-click="restart"
                  class="rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs font-semibold transition hover:border-primary hover:text-primary"
                >
                  Restart
                </button>
              </div>
            </section>

            <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_21rem]">
              <section class="overflow-hidden rounded-[1.5rem] border border-slate-700/70 bg-slate-950 shadow-2xl shadow-slate-950/20">
                <div class="flex items-center justify-between border-b border-white/10 px-4 py-3 text-white">
                  <div>
                    <p class="text-[0.65rem] font-semibold uppercase tracking-[0.22em] text-cyan-300">
                      Mike's work room
                    </p>
                    <p class="mt-1 text-xs text-slate-400">
                      Change {run.revision} · step {run.cursor}
                    </p>
                  </div>
                  <span class={[
                    "size-2.5 rounded-full",
                    if(@mode == :playing, do: "animate-pulse bg-emerald-400", else: "bg-amber-300")
                  ]}></span>
                </div>
                <div
                  id="scenario-stage"
                  phx-hook="ScenarioStage"
                  phx-update="ignore"
                  class="scenario-stage"
                  role="img"
                  aria-label="Picture of Mike and the work cell doing the job"
                >
                  <p class="scenario-stage-fallback">Starting the visual simulation…</p>
                </div>
              </section>

              <aside class="space-y-4">
                <section class="panel">
                  <p class="eyebrow">Current step</p>
                  <h2 class="section-title">
                    {beat_label(run.current_beat)}
                  </h2>
                  <p
                    id="narration"
                    aria-live="polite"
                    class="mt-3 text-sm leading-6 text-base-content/75"
                  >
                    {projection.narration}
                  </p>
                </section>

                <section id="transport-controls" class="panel">
                  <p class="eyebrow">Story controls</p>
                  <div class="mt-4 grid grid-cols-3 gap-2">
                    <button
                      id="step"
                      phx-click="step"
                      disabled={!projection.controls.can_step}
                      class="transport-button"
                    >
                      <.icon name="hero-forward-mini" class="size-4" /> Step
                    </button>
                    <button
                      id="play"
                      phx-click="play"
                      disabled={!projection.controls.can_play || @mode == :playing}
                      class="transport-button transport-button-primary"
                    >
                      <.icon name="hero-play-mini" class="size-4" /> Play
                    </button>
                    <button
                      id="pause"
                      phx-click="pause"
                      disabled={@mode == :paused}
                      class="transport-button"
                    >
                      <.icon name="hero-pause-mini" class="size-4" /> Pause
                    </button>
                  </div>
                  <p class="mt-3 text-xs text-base-content/50">
                    Player: <span id="player-mode" class="font-semibold">{@mode}</span>
                  </p>
                </section>

                <section
                  :if={projection.controls.choices != []}
                  id="decision-panel"
                  class="rounded-2xl border border-amber-300/60 bg-amber-50 p-5 text-amber-950 shadow-sm dark:bg-amber-950 dark:text-amber-50"
                >
                  <p class="text-xs font-semibold uppercase tracking-[0.18em]">Mike must choose</p>
                  <h2 class="mt-2 text-lg font-semibold">The checker found a missing part.</h2>
                  <p class="mt-2 text-sm opacity-75">What should Mike do next?</p>
                  <div class="mt-4 grid gap-2">
                    <button
                      :for={choice <- projection.controls.choices}
                      id={"choice-#{choice.id}"}
                      phx-click="choose"
                      phx-value-choice={choice.id}
                      class="rounded-lg bg-amber-900 px-3 py-2 text-sm font-semibold text-white transition hover:bg-amber-800 dark:bg-amber-300 dark:text-amber-950"
                    >
                      {choice.label}
                    </button>
                  </div>
                </section>

                <p
                  :if={@error}
                  id="simulation-error"
                  role="alert"
                  class="rounded-xl border border-error/30 bg-error/10 p-3 text-sm text-error"
                >
                  {@error}
                </p>
              </aside>
            </div>
          </div>
      <% end %>
    </Layouts.app>
    """
  end
end
