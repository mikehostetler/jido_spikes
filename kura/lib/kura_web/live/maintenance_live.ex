defmodule KuraWeb.MaintenanceLive do
  use KuraWeb, :live_view

  alias Kura.Maintenance
  alias Kura.Playbooks

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Maintenance.subscribe()
    {:ok, assign(socket, page_title: "Maintenance", running: false, case_id: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:case_id, params["case"]) |> refresh()}
  end

  @impl true
  def handle_event("apply_fixture", _params, %{assigns: %{running: true}} = socket),
    do: {:noreply, socket}

  def handle_event("apply_fixture", %{"fixture" => id}, socket) do
    case_id = socket.assigns.case_record && socket.assigns.case_record.id

    {:noreply,
     socket
     |> assign(:running, true)
     |> start_async(:apply_fixture, fn -> Maintenance.apply_fixture(id, case_id) end)}
  end

  def handle_event("open_pool", _params, %{assigns: %{running: false}} = socket) do
    {:noreply,
     socket
     |> assign(:running, true)
     |> start_async(:open_pool, fn -> Maintenance.open_pool() end)}
  end

  def handle_event("open_pool", _params, socket), do: {:noreply, socket}

  def handle_event("replay_candidate", %{"id" => id}, socket) do
    {:noreply,
     start_async(socket, :playbook, fn ->
       Playbooks.replay("cedar", id)
     end)}
  end

  def handle_event("approve_candidate", %{"id" => id}, socket) do
    {:noreply, start_async(socket, :playbook, fn -> Playbooks.approve("cedar", id) end)}
  end

  @impl true
  def handle_async(:apply_fixture, {:ok, {:ok, _record}}, socket),
    do: {:noreply, socket |> assign(:running, false) |> refresh()}

  def handle_async(:apply_fixture, {:ok, {:error, :fixture_out_of_order}}, socket),
    do: {:noreply, socket |> assign(:running, false) |> refresh()}

  def handle_async(:apply_fixture, _result, socket) do
    {:noreply,
     socket
     |> assign(:running, false)
     |> put_flash(:error, "Kura could not load the fixture. Try again.")}
  end

  def handle_async(:playbook, {:ok, {:ok, _version}}, socket), do: {:noreply, refresh(socket)}

  def handle_async(:playbook, _error, socket),
    do: {:noreply, put_flash(socket, :error, "Kura could not replay or approve this candidate.")}

  def handle_async(:open_pool, {:ok, {:ok, [first | _]}}, socket) do
    {:noreply,
     socket |> assign(:running, false) |> push_patch(to: ~p"/maintenance?case=#{first.id}")}
  end

  def handle_async(:open_pool, _error, socket) do
    {:noreply,
     socket
     |> assign(:running, false)
     |> refresh()
     |> put_flash(:error, "Kura could not open a new set of fixture cases.")}
  end

  @impl true
  def handle_info(:maintenance_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    record = Maintenance.fetch(socket.assigns.case_id) || Maintenance.current()
    portfolio = Maintenance.portfolio()
    open_cases = Enum.count(portfolio, &(&1.state["phase"] != "closed"))
    versions = Playbooks.versions("cedar", "ci_triage")
    pending = Maintenance.pending(record)
    events = if record, do: record.state["events"], else: []
    {assessments, history} = Enum.split_with(events, &get_in(&1, ["evidence", "trace"]))

    assign(socket,
      case_record: record,
      portfolio: portfolio,
      open_cases: open_cases,
      workers: Maintenance.workers(),
      state: record && record.state,
      history: history,
      assessments: assessments,
      playbook: record && record.state["playbook"],
      active_version: Enum.find(versions, & &1.active),
      candidates: Enum.reject(versions, & &1.approved),
      earlier_versions: Enum.filter(versions, &(&1.approved and not &1.active)),
      manual_review: Maintenance.fixture_review_available?(record),
      pending: pending,
      next: Maintenance.next_fixture(record, pending)
    )
  end

  defp phase("waiting_review"), do: "Waiting for Review"
  defp phase("waiting_ci"), do: "Waiting for CI"
  defp phase("closed"), do: "Closed"
  defp phase("blocked"), do: "Blocked"

  defp sha(commit), do: String.slice(commit, 0, 12)

  defp worker_label("cedar/review"), do: "Review 1"
  defp worker_label("cedar/review-2"), do: "Review 2"
  defp worker_label("cedar/review-3"), do: "Review 3"

  defp trigger("ci_snapshot"), do: "CI snapshot"
  defp trigger("review_reply"), do: "Review reply"
  defp trigger("case_closed"), do: "Case closure"

  defp method_label("ask_review"), do: "Ask Review"
  defp method_label("use_ci_evidence"), do: "Use CI evidence"
  defp method_label(method), do: method

  defp case_summary(%{"phase" => "closed"}),
    do: "CI passed on the new commit. The case is closed."

  defp case_summary(%{"phase" => "waiting_review"}),
    do: "Cedar saved a request for Review to inspect the test failure."

  defp case_summary(%{"phase" => "blocked"}),
    do: "Cedar could not finish triage. See the case history for the error."

  defp case_summary(%{"fixtures" => fixtures}) do
    if "stale_pass" in fixtures,
      do: "The pass was for the old commit. Cedar is waiting for CI on the current commit.",
      else: "Cedar is waiting for a passing check on a new commit."
  end

  defp learned_rule(%{
         evidence: %{"change" => %{"method" => "ask_review", "condition" => "missing_assertion"}}
       }),
       do:
         "Use CI evidence when it includes what the test expected and what it received. Ask Review when that detail is missing."

  defp learned_rule(%{evidence: %{"source" => "seed"}}),
    do: "Ask Review for the test details on every failed check."

  defp learned_rule(_version), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="min-h-screen bg-base-200">
      <header class="border-b border-base-300 bg-base-100">
        <div class="mx-auto flex max-w-5xl items-center justify-between px-4 py-4 sm:px-6">
          <div class="flex items-baseline gap-3">
            <span class="text-xl font-semibold tracking-tight">Kura</span>
            <span class="border-l border-base-300 pl-3 text-sm text-base-content/70">Maintenance</span>
          </div>
          <.link navigate={~p"/cells"} class="link link-hover text-sm">Work cells</.link>
        </div>
      </header>

      <main class="mx-auto max-w-5xl space-y-5 p-4 sm:p-6">
        <section
          class="border border-base-300 bg-base-100 p-5 sm:p-6"
          aria-labelledby="portfolio-title"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 id="portfolio-title" class="text-lg font-semibold">Cedar's case portfolio</h2>
              <p class="mt-1 text-sm text-base-content/70">Cedar coordinates three child Holons.</p>
            </div>
            <button
              :if={@open_cases == 0}
              id="open-maintenance-pool"
              type="button"
              class="btn btn-sm btn-outline rounded-sm"
              phx-click="open_pool"
              disabled={@running}
            >
              Load 10 fixture cases
            </button>
            <p :if={@portfolio != []} id="portfolio-count" class="text-sm font-medium">
              {@open_cases} open · {length(@portfolio)} total
            </p>
          </div>
          <div :if={@portfolio != []} class="mt-4 grid gap-3 md:grid-cols-3">
            <section
              :for={worker <- @workers}
              data-worker={worker}
              class="border border-base-300 p-3"
            >
              <h3 class="text-sm font-semibold">{worker_label(worker)}</h3>
              <ul class="mt-2 space-y-1">
                <li :for={record <- Enum.filter(@portfolio, &(Maintenance.worker_id(&1) == worker))}>
                  <.link
                    patch={~p"/maintenance?case=#{record.id}"}
                    data-case={record.id}
                    aria-current={if @case_record && @case_record.id == record.id, do: "true"}
                    class={[
                      "flex justify-between gap-2 px-2 py-1 text-sm hover:bg-base-200",
                      @case_record && @case_record.id == record.id && "bg-base-200 font-medium"
                    ]}
                  >
                    <span>Case {record.state["slot"]}</span>
                    <span class="text-xs text-base-content/70">{phase(record.state["phase"])}</span>
                  </.link>
                </li>
              </ul>
            </section>
          </div>
        </section>

        <section aria-labelledby="case-title" class="border border-base-300 bg-base-100 p-5 sm:p-6">
          <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
            <h1 id="case-title" class="text-2xl font-semibold tracking-tight">
              {if @state && @state["slot"], do: "Case #{@state["slot"]}", else: "Delivery test"}
            </h1>
            <span
              :if={@state}
              id="maintenance-status"
              aria-live="polite"
              class={[
                "badge rounded-sm",
                case @state["phase"] do
                  "closed" -> "badge-success"
                  "blocked" -> "badge-error"
                  _ -> "badge-warning"
                end
              ]}
            >{phase(@state["phase"])}</span>
          </div>
          <p class="mt-2 max-w-prose text-sm leading-relaxed text-base-content/80">
            {if @state,
              do: case_summary(@state),
              else: "Choose a local CI report to see how Cedar investigates a failed test."}
          </p>
          <dl :if={@state} class="mt-4 flex flex-wrap gap-x-5 gap-y-1 text-xs text-base-content/70">
            <div :if={@state["worker"]} class="flex items-baseline gap-2">
              <dt>Assigned worker</dt>
              <dd>{worker_label(@state["worker"])}</dd>
            </div>
            <div class="flex items-baseline gap-2">
              <dt>Failed commit</dt>
              <dd><code title={@state["original_head"]}>{sha(@state["original_head"])}</code></dd>
            </div>
            <div class="flex items-baseline gap-2">
              <dt>Current commit</dt>
              <dd>
                <code id="maintenance-head" title={@state["current_head"]}>{sha(
                  @state["current_head"]
                )}</code>
              </dd>
            </div>
          </dl>

          <div :if={@playbook} id="loom-run" class="mt-5 border-l-2 border-primary/50 pl-4 text-sm">
            <h2 class="font-semibold">
              {method_label(@playbook["result"]["method"])} · Playbook v{@playbook["version"]}
            </h2>
            <p
              :if={learned = @playbook["learned_from"]}
              id="cedar-learned-replay"
              data-version={learned["version_id"]}
              data-learning-pulse={learned["pulse_id"]}
              data-replay-pulse={@playbook["run_id"]}
              class="mt-1 text-xs text-base-content/70"
            >
              Loom replayed the playbook Cedar learned with Tune.
            </p>
            <p
              :if={@playbook["result"]["finding"] || @playbook["question"]}
              class="mt-1 max-w-prose text-base-content/80"
            >
              {@playbook["result"]["finding"] || @playbook["question"]}
            </p>
          </div>

          <div class="mt-5 flex flex-wrap items-center gap-2">
            <button
              :if={@next}
              id="maintenance-next"
              type="button"
              class="btn btn-primary rounded-sm"
              phx-click="apply_fixture"
              phx-value-fixture={@next["id"]}
              phx-disable-with="Loading"
              disabled={@running}
            >
              {if @next["id"] == "failure", do: "Load detailed CI failure", else: @next["label"]}
            </button>
            <button
              :if={@next && @next["id"] == "failure"}
              type="button"
              class="btn btn-outline rounded-sm"
              phx-click="apply_fixture"
              phx-value-fixture="failure_sparse"
              phx-disable-with="Loading"
              disabled={@running}
            >
              Load CI failure summary
            </button>
            <button
              :if={@manual_review}
              type="button"
              class="btn btn-primary rounded-sm"
              phx-click="apply_fixture"
              phx-value-fixture="review_reply"
              phx-disable-with="Loading"
              disabled={@running}
            >
              Deliver Review reply
            </button>
            <p :if={@pending != []} role="status" class="text-sm text-base-content/70">
              Cedar is processing {trigger(hd(@pending)["type"])}.
            </p>
          </div>
        </section>

        <div class="grid items-start gap-5 md:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          <section
            :if={@state}
            class="min-w-0 border border-base-300 bg-base-100 p-5"
            aria-labelledby="maintenance-history"
          >
            <h2 id="maintenance-history" class="text-lg font-semibold">What happened</h2>
            <ol id="maintenance-events" class="mt-2 divide-y divide-base-300">
              <.history_event :for={event <- @history} event={event} />
            </ol>
            <details :if={@assessments != []} class="border-t border-base-300 pt-3 text-sm">
              <summary class="cursor-pointer font-medium">
                Cedar's assessments ({length(@assessments)})
              </summary>
              <ol class="mt-1 divide-y divide-base-300 pl-3">
                <.assessment :for={event <- @assessments} event={event} />
              </ol>
            </details>
          </section>

          <aside id="playbook-versions" class="min-w-0 border border-base-300 bg-base-100 p-5">
            <h2 class="text-lg font-semibold">What Cedar learned</h2>
            <p :if={!@active_version} class="mt-2 text-sm text-base-content/70">
              Start a case to load the playbook.
            </p>
            <.playbook_version
              :if={@active_version}
              version={@active_version}
              label="Active playbook"
            />
            <.playbook_version
              :for={version <- @candidates}
              version={version}
              label="Proposed change"
            />
            <details :if={@earlier_versions != []} class="mt-4 border-t border-base-300 pt-3 text-sm">
              <summary class="cursor-pointer font-medium">Earlier versions</summary>
              <.playbook_version
                :for={version <- @earlier_versions}
                version={version}
                label="Approved playbook"
              />
            </details>
          </aside>
        </div>

        <details :if={@state} class="border border-base-300 bg-base-100 px-5 py-4 text-sm">
          <summary class="cursor-pointer font-medium">Run details</summary>
          <dl class="mt-3 grid gap-2 text-xs text-base-content/70">
            <div>
              <dt>Case ID</dt><dd>
                <code id="maintenance-id" class="break-all">{@case_record.id}</code>
              </dd>
            </div>
            <div :if={@playbook}>
              <dt>Loom run ID</dt><dd>
                <code id="loom-run-id" class="break-all">{@playbook["run_id"]}</code>
              </dd>
            </div>
            <div :if={@playbook && @playbook["wait_id"]}>
              <dt>Wait ID</dt><dd>
                <code id="loom-wait-id" class="break-all">{@playbook["wait_id"]}</code>
              </dd>
            </div>
          </dl>
          <p :if={@pending == []} id="pulse-idle" class="mt-3 text-xs text-base-content/70">
            No pending pulses
          </p>
          <ul
            :if={@pending != []}
            id="pulse-inbox"
            class="mt-3 space-y-1 text-xs text-base-content/70"
          >
            <li :for={pulse <- @pending} data-pending-pulse={pulse["id"]} class="break-all">
              {trigger(pulse["type"])} · <code>{pulse["id"]}</code>
            </li>
          </ul>
        </details>
      </main>
    </div>
    """
  end

  defp assessment(assigns) do
    ~H"""
    <li class="py-2.5 text-sm">
      <details>
        <summary class="cursor-pointer text-base-content/70">
          {if @event["evidence"]["trigger"],
            do: trigger(@event["evidence"]["trigger"]),
            else: "Cognitive pulse"}
        </summary>
        <p :if={learning = get_in(@event, ["evidence", "trace", "learning"])} class="mt-2">
          {learning["reason"] || @event["evidence"]["trace"]["output"]}
        </p>
        <.react_trace
          :if={!get_in(@event, ["evidence", "trace", "learning"])}
          evidence={@event["evidence"]}
        />
      </details>
    </li>
    """
  end

  defp history_event(assigns) do
    ~H"""
    <li class="py-3 text-sm">
      <p class="text-xs font-semibold text-primary">{@event["actor"]}</p>
      <p class="mt-1 font-medium">{@event["message"]}</p>
      <p :if={@event["evidence"]["error"]} class="mt-1 break-all text-base-content/70">
        {@event["evidence"]["error"]}
      </p>
      <p :if={@event["evidence"]["evidence"]} class="mt-1 text-base-content/70">
        {@event["evidence"]["evidence"]}
      </p>
      <details
        :if={@event["evidence"]["check_head"] || @event["evidence"]["receipt"]}
        class="mt-1 text-xs text-base-content/70"
      >
        <summary class="cursor-pointer">Evidence details</summary>
        <p :if={commit = @event["evidence"]["check_head"]} class="mt-1">
          Check commit <code title={commit}>{sha(commit)}</code>
        </p>
        <p :if={receipt = @event["evidence"]["receipt"]} class="mt-1">
          Jido VSM receipt <code class="break-all">{receipt}</code>
        </p>
      </details>
    </li>
    """
  end

  defp playbook_version(assigns) do
    ~H"""
    <article class="mt-4 border-t border-base-300 pt-3 text-sm" data-version={@version.id}>
      <h3 class="font-semibold">{@label} · v{@version.revision}</h3>
      <p :if={rule = learned_rule(@version)} class="mt-1 leading-relaxed text-base-content/80">
        {rule}
      </p>
      <div
        :if={@version.evidence["source"] == "tune"}
        data-tune-learning={@version.evidence["pulse_id"]}
        class="mt-2 text-xs text-base-content/70"
      >
        <p>Tune scored both methods using Cedar's saved traces and a sparse CI fixture.</p>
        <p class="mt-1">
          Baseline {@version.evidence["scores"]["baseline"]} · Guarded {@version.evidence["scores"][
            "guarded"
          ]}
        </p>
        <details class="mt-1">
          <summary class="cursor-pointer">Source pulses</summary>
          <p class="mt-1 break-all">
            CI <code>{@version.evidence["observations"]["ci_pulse_id"]}</code>
          </p>
          <p class="mt-1 break-all">
            Review <code>{@version.evidence["observations"]["review_pulse_id"]}</code>
          </p>
        </details>
      </div>
      <details :if={@version.replay || @version.evidence["case_id"]} class="mt-2">
        <summary class="cursor-pointer text-xs text-base-content/70">
          {cond do
            @version.replay && @version.replay["passed"] -> "Replay passed"
            @version.replay -> "Replay failed"
            true -> "Source case"
          end}
        </summary>
        <p :if={@version.evidence["case_id"]} class="mt-2 break-all text-xs text-base-content/70">
          Source case <code>{@version.evidence["case_id"]}</code>
        </p>
        <dl :if={replay = @version.replay} class="mt-2 space-y-2 text-xs">
          <div :for={
            {fixture, label} <- [{"detailed", "Detailed report"}, {"sparse", "Summary only"}]
          }>
            <dt class="font-medium">{label}</dt>
            <dd class="mt-0.5 text-base-content/70">
              {method_label(get_in(replay, ["baseline", fixture, "method"]))} → {method_label(
                get_in(replay, ["candidate", fixture, "method"])
              )}
            </dd>
          </div>
          <div>
            <dt class="font-medium">Exact-commit CI rule</dt>
            <dd class="mt-0.5 text-base-content/70">
              {if replay["exact_commit_gate"], do: "Passed", else: "Failed"}
            </dd>
          </div>
        </dl>
      </details>
      <div :if={!@version.approved} class="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          class="btn btn-sm btn-outline rounded-sm"
          phx-click="replay_candidate"
          phx-value-id={@version.id}
          phx-disable-with="Replaying"
        >
          Replay fixtures
        </button>
        <button
          :if={@version.replay && @version.replay["passed"]}
          type="button"
          class="btn btn-sm btn-primary rounded-sm"
          phx-click="approve_candidate"
          phx-value-id={@version.id}
          phx-disable-with="Approving"
        >
          Approve v{@version.revision}
        </button>
      </div>
    </article>
    """
  end

  defp react_trace(assigns) do
    assigns = assign(assigns, :trace, assigns.evidence["trace"])

    ~H"""
    <div
      data-react-trace
      data-pulse-id={@evidence["pulse_id"]}
      data-pulse-trigger={@evidence["trigger"]}
      class="mt-2 border border-base-300 bg-base-200 p-3"
    >
      <p class="flex flex-wrap items-baseline gap-x-2 text-xs">
        <span class="font-semibold">ReAct trace</span>
        <span :if={@evidence["trigger"]} class="text-base-content/70">{trigger(@evidence["trigger"])}</span>
        <code class="text-base-content/70">{@trace["model"] || "Local demo"}</code>
        <span class="text-base-content/70">{@trace["status"]}</span>
      </p>
      <code :if={@evidence["pulse_id"]} class="mt-1 block break-all text-xs text-base-content/60">
        {@evidence["pulse_id"]}
      </code>
      <p :if={is_binary(@trace["output"])} class="mt-2 whitespace-pre-wrap">{@trace["output"]}</p>
      <p :if={@trace["tools"] == []} class="mt-2 text-xs text-base-content/70">No tool call</p>
      <div :for={tool <- @trace["tools"]} class="mt-2 border-t border-base-300 pt-2 text-xs">
        <p><code>{tool["name"]}({JSON.encode!(tool["arguments"])})</code> · {tool["status"]}</p>
        <pre class="mt-1 whitespace-pre-wrap break-all">{JSON.encode!(tool["result"])}</pre>
      </div>
    </div>
    """
  end
end
