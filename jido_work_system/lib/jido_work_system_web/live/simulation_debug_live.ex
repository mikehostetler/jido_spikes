defmodule JidoWorkSystemWeb.SimulationDebugLive do
  use JidoWorkSystemWeb, :live_view

  alias JidoWorkSystem.Simulation

  @impl true
  def mount(%{"id" => run_id}, _session, socket) do
    case Simulation.get_run(run_id) do
      {:ok, state} ->
        {:ok,
         assign(socket,
           page_title: "Full Story Details",
           state: state,
           snapshot: state.snapshot,
           missing?: false
         )}

      {:error, :not_found} ->
        {:ok,
         assign(socket,
           page_title: "Run Not Found",
           state: nil,
           snapshot: nil,
           missing?: true
         )}
    end
  end

  defp first([value | _]), do: value
  defp first([]), do: nil

  defp find(items, id), do: Enum.find(items, &(&1.id == id))

  defp method_name(snapshot, id) do
    case find(snapshot.methods, id) do
      nil -> "Unknown"
      method -> method.name
    end
  end

  defp depth(%{parent_id: nil}, _cells, value), do: value

  defp depth(cell, cells, value) do
    case find(cells, cell.parent_id) do
      nil -> value
      parent -> depth(parent, cells, value + 1)
    end
  end

  defp sorted_cells(cells), do: Enum.sort_by(cells, &{depth(&1, cells, 0), &1.name})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @missing? do %>
        <section id="debug-not-found" class="panel text-center">
          <p class="eyebrow">Full details</p>
          <h1 class="section-title">This story does not exist.</h1>
          <.link
            navigate={~p"/"}
            class="mt-4 inline-flex rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-content"
          >
            Return to stories
          </.link>
        </section>
      <% else %>
        <% snapshot = @snapshot %>
        <% run = @state.run %>
        <% task = first(snapshot.tasks) %>
        <% human = first(snapshot.humans) %>
        <% role = first(snapshot.roles) %>
        <% authority = first(snapshot.authorities) %>
        <% accountability = first(snapshot.accountabilities) %>
        <% delegation = first(snapshot.delegations) %>
        <% workspace = first(snapshot.workspaces) %>
        <% tool = first(snapshot.tools) %>
        <% knowledge = first(snapshot.knowledge) %>
        <% outcome = first(snapshot.outcomes) %>

        <div id="simulation-debug" class="space-y-5">
          <section class="flex flex-col gap-4 rounded-2xl bg-neutral p-6 text-neutral-content shadow-sm lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p class="eyebrow text-neutral-content">Full story details</p>
              <h1 class="mt-2 text-3xl font-semibold">{@state.projection.scenario.title}</h1>
              <p class="mt-2 text-sm opacity-75">
                Change {run.revision} · step {run.cursor} · {run.status}
              </p>
            </div>
            <.link
              navigate={~p"/runs/#{run.id}"}
              class="rounded-lg border border-white/25 px-4 py-2 text-sm font-semibold transition hover:bg-white/10"
            >
              Back to the story
            </.link>
          </section>

          <section id="debug-summary" class="grid gap-4 md:grid-cols-4">
            <div class="panel">
              <p class="eyebrow">Steps</p><p class="mt-2 text-3xl font-semibold">
                {length(snapshot.events)}
              </p>
            </div>
            <div class="panel">
              <p class="eyebrow">Choices</p><p class="mt-2 text-3xl font-semibold">
                {length(snapshot.judgments)}
              </p>
            </div>
            <div class="panel">
              <p class="eyebrow">Changes</p><p class="mt-2 text-3xl font-semibold">
                {length(snapshot.mutations)}
              </p>
            </div>
            <div class="panel">
              <p class="eyebrow">Notes checked</p><p class="mt-2 text-3xl font-semibold">
                {length(snapshot.evidence)}
              </p>
            </div>
          </section>

          <section class="grid gap-4 lg:grid-cols-2">
            <article id="accountability" class="panel">
              <p class="eyebrow">Who owns the job</p>
              <h2 class="section-title">{human.name} · {role.name}</h2>
              <dl class="detail-grid">
                <dt>Mike owns</dt><dd>{accountability.subject}</dd>
                <dt>Can say it is done</dt><dd>{to_string(accountability.acceptance_right)}</dd>
                <dt>Job rules</dt><dd>{authority.name}</dd>
                <dt>Rule limits</dt><dd>{authority.limits}</dd>
              </dl>
            </article>

            <article id="topology" class="panel">
              <p class="eyebrow">Work cells</p>
              <h2 class="section-title">Who does the job</h2>
              <div class="mt-3 space-y-2">
                <div
                  :for={cell <- sorted_cells(snapshot.cells)}
                  class="rounded-lg border border-base-300 px-3 py-2"
                  style={"margin-left: #{depth(cell, snapshot.cells, 0) * 1.25}rem"}
                >
                  <strong>{cell.name}</strong>
                  <span class="ml-2 text-xs opacity-55">VSM: {cell.vsm_cell_id}</span>
                </div>
              </div>
            </article>
          </section>

          <article id="task" class="panel">
            <p class="eyebrow">The job</p>
            <%= if task do %>
              <div class="mt-1 flex flex-wrap items-start justify-between gap-3">
                <h2 class="section-title">{task.title}</h2>
                <span class="rounded-full bg-primary/15 px-3 py-1 text-xs font-semibold text-primary">{task.status}</span>
              </div>
              <dl class="detail-grid mt-4 md:grid-cols-[12rem_1fr]">
                <dt>Why</dt><dd>{task.purpose}</dd>
                <dt>Mike needs</dt><dd>{task.required_output}</dd>
                <dt>How much</dt><dd>{task.quantity}</dd>
                <dt>What good means</dt><dd>{task.quality}</dd>
                <dt>Cell said</dt><dd>
                  {if delegation, do: delegation.status, else: "not offered"}
                </dd>
              </dl>
            <% else %>
              <p class="mt-3 text-sm opacity-65">Mike has not explained the job yet.</p>
            <% end %>
          </article>

          <section class="grid gap-4 lg:grid-cols-2">
            <article class="panel">
              <p class="eyebrow">What the cell can use</p>
              <h2 class="section-title">Safe work area</h2>
              <dl class="detail-grid">
                <dt>Work area</dt><dd>{workspace.root}</dd>
                <dt>Rule</dt><dd>{workspace.boundary}</dd>
                <dt>Tool</dt><dd>{tool.name}</dd>
                <dt>Can write here</dt><dd class="font-mono text-xs">{tool.allowed_path}</dd>
                <dt>Facts</dt><dd>{knowledge.content}</dd>
              </dl>
            </article>

            <article id="outcome" class="panel">
              <p class="eyebrow">How it ended</p>
              <h2 class="section-title">Mike's final choice</h2>
              <%= if outcome do %>
                <p id="outcome-status" class="mt-3 text-lg font-semibold">
                  {outcome.human_acceptance}
                </p>
                <p class="mt-1 text-sm opacity-70">{outcome.summary}</p>
              <% else %>
                <p class="mt-3 text-sm opacity-65">The job is not done yet.</p>
              <% end %>
            </article>
          </section>

          <article id="judgments" class="panel">
            <p class="eyebrow">Choices and tools</p>
            <h2 class="section-title">Why the cell made each choice</h2>
            <div class="mt-4 grid gap-3 lg:grid-cols-2">
              <div :for={judgment <- snapshot.judgments} class="rounded-xl border border-base-300 p-4">
                <div class="flex justify-between gap-3">
                  <strong>{judgment.situation}</strong>
                  <span class="rounded-full border border-base-300 px-2 py-1 text-xs">{method_name(
                    snapshot,
                    judgment.method_id
                  )}</span>
                </div>
                <p class="mt-2 text-sm">{judgment.decision_text}</p>
                <p class="mt-1 text-xs opacity-60">{judgment.stated_basis}</p>
              </div>
              <p :if={snapshot.judgments == []} class="text-sm opacity-65">
                The cell has not made a choice yet.
              </p>
            </div>
          </article>

          <article id="evidence" class="panel">
            <p class="eyebrow">The note and its checks</p>
            <h2 class="section-title">The checker looks at the work</h2>
            <div class="mt-4 grid gap-3 lg:grid-cols-2">
              <div
                :for={item <- snapshot.evidence}
                class="rounded-xl border border-base-300 p-4 text-sm"
              >
                <strong>{item.kind}</strong>
                <p class="mt-2">{item.content}</p>
                <p class="mt-2 text-xs opacity-60">{item.source}</p>
              </div>
              <div
                :for={item <- snapshot.evaluations}
                class="rounded-xl border border-base-300 p-4 text-sm"
              >
                <strong>{item.verification_status}</strong>
                <p class="mt-2">{item.verdict}</p>
                <p class="mt-2 text-xs opacity-60">
                  How sure: {Decimal.to_string(item.confidence)} · {item.notes}
                </p>
              </div>
            </div>
          </article>

          <article id="timeline" class="panel">
            <p class="eyebrow">Story steps</p>
            <h2 class="section-title">What happened, in order</h2>
            <ol class="mt-4 space-y-3">
              <li
                :for={event <- snapshot.events}
                id={"event-#{event.sequence}"}
                data-kind={event.kind}
                class="grid grid-cols-[2rem_minmax(7rem,10rem)_1fr] items-start gap-3 text-sm"
              >
                <span class="grid size-7 place-items-center rounded-full bg-neutral font-mono text-xs text-neutral-content">{event.sequence}</span>
                <code class="pt-1 text-xs">{event.kind}</code>
                <span>{event.summary}</span>
              </li>
            </ol>
          </article>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
