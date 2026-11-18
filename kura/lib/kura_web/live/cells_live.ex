defmodule KuraWeb.CellsLive do
  use KuraWeb, :live_view

  alias Kura.{Cells, Playbooks}
  alias Kura.Cell.Cognition

  @impl true
  def mount(_params, _session, socket) do
    cells = Cells.all()

    if connected?(socket) do
      for cell <- cells do
        Phoenix.PubSub.subscribe(Kura.PubSub, "cell:" <> cell.id)
      end
    end

    {:ok, assign(socket, cells: cells)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case Cells.fetch(Map.get(params, "id", "cedar")) do
      {:ok, cell} ->
        {:noreply,
         socket
         |> assign(cell: cell, role: cell.role_text, model: Cognition.model(cell))
         |> load_history()}

      {:error, :unknown_cell} ->
        {:noreply, redirect(socket, to: ~p"/cells")}
    end
  end

  @impl true
  def handle_event("inspect", _params, socket) do
    {:noreply, after_input(socket, Cells.command(socket.assigns.cell.id, :inspect))}
  end

  def handle_event("observe", _params, socket) do
    {:noreply, after_input(socket, Cells.command(socket.assigns.cell.id, :observe))}
  end

  def handle_event("observation_playbook", %{"id" => id, "action" => action}, socket)
      when action in ["replay", "approve"] do
    cell = socket.assigns.cell.id

    {:noreply,
     start_async(socket, {:observation_playbook, cell}, fn ->
       with {:ok, %{task: "record_observation"}} <- Playbooks.get(cell, id) do
         case action do
           "replay" -> Playbooks.replay(cell, id)
           "approve" -> Playbooks.approve(cell, id)
         end
       else
         _ -> {:error, :unknown_version}
       end
     end)}
  end

  def handle_event("chat", %{"message" => message}, socket) do
    cell_id = socket.assigns.cell.id

    {:noreply, start_async(socket, {:chat, cell_id}, fn -> Cells.chat(cell_id, message) end)}
  end

  def handle_event("remember", %{"note" => note}, socket) do
    {:noreply, after_input(socket, Cells.remember(socket.assigns.cell.id, note))}
  end

  @impl true
  def handle_async({:chat, cell_id}, outcome, socket) do
    if socket.assigns.cell.id == cell_id do
      case outcome do
        {:ok, result} -> {:noreply, after_input(socket, result)}
        {:exit, _reason} -> {:noreply, put_flash(socket, :error, "Chat did not complete.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:observation_playbook, cell}, outcome, socket) do
    if socket.assigns.cell.id == cell do
      case outcome do
        {:ok, result} -> {:noreply, after_input(socket, result)}
        {:exit, _} -> {:noreply, put_flash(socket, :error, "The playbook request failed.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:cell_changed, socket), do: {:noreply, load_history(socket)}

  defp after_input(socket, {:ok, _entry}), do: load_history(socket)

  defp after_input(socket, {:error, reason}) do
    put_flash(socket, :error, "Request failed: #{inspect(reason, limit: 5)}")
  end

  defp load_history(socket) do
    id = socket.assigns.cell.id

    {latest, previous} =
      case Enum.reverse(Cells.history(id, "command")) do
        [latest | previous] -> {latest, previous}
        [] -> {nil, []}
      end

    states =
      Map.new(socket.assigns.cells, fn cell ->
        entry = if cell.id == id, do: latest, else: Cells.latest_command(cell.id)
        {cell.id, cell_state(entry)}
      end)

    cell = socket.assigns.cell
    inspection? = Map.has_key?(cell.signals, "kura.workspace.inspect")

    observation? =
      Map.has_key?(cell.signals, "kura.workspace.observed") and
        Map.has_key?(cell.playbook_tasks, "record_observation")

    versions = if observation?, do: Playbooks.versions(id, "record_observation"), else: []

    assign(socket,
      inspection?: inspection?,
      observation?: observation?,
      observation_active: Enum.find(versions, & &1.active),
      observation_draft: Enum.find(versions, &(not &1.approved)),
      latest: latest,
      previous: previous,
      states: states,
      chat: Cells.history(id, "chat"),
      memories: Cells.history(id, "memory")
    )
  end

  defp cell_state(%{status: "queued"}), do: "Pending"
  defp cell_state(%{status: "blocked"}), do: "Blocked"
  defp cell_state(_), do: "Idle"

  defp badge_type(status) when status in ["Pending", "Queued"], do: "badge-warning"
  defp badge_type("Blocked"), do: "badge-error"
  defp badge_type("Completed"), do: "badge-success"
  defp badge_type(_), do: "badge-ghost"

  defp run_summary(%{status: "queued"}), do: "Waiting for an inspection result."
  defp run_summary(%{status: "blocked"}), do: "The work stopped before it completed."

  defp run_summary(%{output: output}) do
    output |> to_string() |> String.split([" SHA-256 ", "\n"], parts: 2) |> hd()
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm badge-soft shrink-0 font-medium", badge_type(@status)]}>{@status}</span>
    """
  end

  defp tool_trace(assigns) do
    ~H"""
    <section aria-label="Workspace tool" class="mt-3 space-y-2 border-t border-base-300 pt-3">
      <h4 class="text-xs font-semibold tracking-wide text-base-content/75 uppercase">
        Workspace tool
      </h4>
      <p :if={@trace["tools"] == []} class="text-sm text-base-content/70">
        The model did not call the tool.
      </p>
      <div :for={call <- @trace["tools"]} class="space-y-2">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <code class="wrap-anywhere text-xs text-primary">{call["name"]}({Jason.encode!(
            call["arguments"]
          )})</code>
          <.status_badge status={if call["status"] == "ok", do: "Completed", else: "Blocked"} />
        </div>
        <pre class="wrap-anywhere whitespace-pre-wrap font-mono text-xs text-base-content/80">{Jason.encode!(call["result"], pretty: true)}</pre>
      </div>
    </section>
    """
  end

  defp cell_links(assigns) do
    ~H"""
    <ul class="space-y-1">
      <li :for={cell <- @children[@parent] || []}>
        <.link
          patch={~p"/cells?#{[id: cell.id]}"}
          aria-current={if cell.id == @selected, do: "page"}
          class={[
            "flex items-center justify-between gap-2 border-l-2 border-transparent px-2.5 py-2 text-sm hover:bg-base-200",
            cell.id == @selected && "border-l-primary bg-primary/10 font-semibold"
          ]}
        >
          <span class="min-w-0 wrap-break-word">{Path.basename(cell.id)}</span>
          <.status_badge status={Map.fetch!(@states, cell.id)} />
        </.link>
        <div :if={@children[cell.id]} class="mt-1 ml-3 border-l border-base-300 pl-2">
          <.cell_links children={@children} parent={cell.id} selected={@selected} states={@states} />
        </div>
      </li>
    </ul>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="min-h-screen bg-base-200">
      <header class="border-b border-base-300 bg-base-100">
        <div class="mx-auto flex max-w-screen-2xl flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-4 sm:px-6">
          <h1 class="flex items-baseline gap-3">
            <span class="text-xl font-semibold tracking-tight">Kura</span>
            <span class="border-l border-base-300 pl-3 text-sm text-base-content/70">Work cells</span>
          </h1>
          <div class="flex items-center gap-4">
            <.link navigate={~p"/maintenance"} class="link link-hover text-sm">Maintenance</.link>
            <span class="font-mono text-xs text-base-content/70">{@model || "Local demo mode"}</span>
          </div>
        </div>
      </header>

      <main class="mx-auto grid max-w-screen-2xl items-start gap-6 p-4 sm:p-6 md:grid-cols-[minmax(0,1fr)_minmax(16rem,1fr)] lg:grid-cols-[12rem_minmax(0,1fr)_minmax(18rem,22rem)]">
        <nav
          aria-label="Work cells"
          class="border border-base-300 bg-base-100 p-3 md:col-span-2 lg:col-span-1"
        >
          <h2 class="px-3 pt-1 pb-3 text-xs font-semibold tracking-wide text-base-content/70 uppercase">
            Cells
          </h2>
          <.cell_links
            children={Enum.group_by(@cells, & &1.parent)}
            parent={nil}
            selected={@cell.id}
            states={@states}
          />
        </nav>

        <div class="min-w-0 space-y-4">
          <section aria-labelledby="work-title" class="card border border-base-300 bg-base-100">
            <div class="card-body gap-5 p-4 sm:p-6">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p class="wrap-break-word font-mono text-xs text-base-content/65">{@cell.id}</p>
                  <h2 id="work-title" class="mt-1 text-3xl font-semibold tracking-tight">
                    {@cell.name}
                  </h2>
                  <p :if={@cell.parent} class="mt-1 text-sm text-base-content/70">
                    Parent:
                    <.link patch={~p"/cells?#{[id: @cell.parent]}"} class="link link-hover">{@cell.parent}</.link>
                  </p>
                </div>
                <.status_badge status={Map.fetch!(@states, @cell.id)} />
              </div>

              <button
                :if={@inspection?}
                type="button"
                phx-click="inspect"
                class="btn btn-primary btn-sm self-start"
              >
                <.icon name="hero-magnifying-glass" class="size-4" /> Inspect workspace
              </button>

              <section :if={@observation?} class="space-y-2 border-t border-base-300 pt-3">
                <h3 class="font-semibold">Workspace observation playbook</h3>
                <button
                  :if={!@observation_draft || @observation_active}
                  type="button"
                  phx-click="observe"
                  disabled={@latest && @latest.status == "queued"}
                  class="btn btn-outline btn-sm"
                >
                  {if @observation_active, do: "Run approved playbook", else: "Create a draft"}
                </button>
                <div :if={@observation_draft && !@observation_active} class="flex flex-wrap gap-2">
                  <button
                    type="button"
                    phx-click="observation_playbook"
                    phx-value-id={@observation_draft.id}
                    phx-value-action="replay"
                    class="btn btn-outline btn-sm"
                  >
                    Replay fixture
                  </button>
                  <button
                    :if={@observation_draft.replay && @observation_draft.replay["passed"]}
                    type="button"
                    phx-click="observation_playbook"
                    phx-value-id={@observation_draft.id}
                    phx-value-action="approve"
                    class="btn btn-primary btn-sm"
                  >
                    Approve
                  </button>
                </div>
              </section>

              <section
                aria-live="polite"
                aria-labelledby="latest-run-title"
                class="border-l-2 border-l-base-300 bg-base-200/80 px-4 py-3.5"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <h3
                    id="latest-run-title"
                    class="text-xs font-semibold tracking-wide text-base-content/75 uppercase"
                  >
                    Latest run
                  </h3>
                  <.status_badge :if={@latest} status={String.capitalize(@latest.status)} />
                </div>
                <p :if={!@latest} class="mt-2 text-sm text-base-content/70">No work has run.</p>
                <p :if={@latest} class="mt-2 wrap-break-word text-base">{run_summary(@latest)}</p>
                <.tool_trace :if={@latest && @latest.trace} trace={@latest.trace} />
                <details :if={@latest && @latest.output} class="mt-3">
                  <summary class="link link-hover cursor-pointer text-sm font-medium">
                    View evidence
                  </summary>
                  <p class="mt-2 wrap-anywhere whitespace-pre-line font-mono text-xs leading-relaxed text-base-content/80">
                    {@latest.output}
                  </p>
                </details>
              </section>

              <details :if={@previous != []} class="collapse collapse-arrow border-y border-base-300">
                <summary class="collapse-title min-h-0 py-3 text-sm font-medium">
                  Run history ({length(@previous)})
                </summary>
                <div class="collapse-content">
                  <details :for={entry <- @previous} class="border-t border-base-300 py-2">
                    <summary class="cursor-pointer text-sm">
                      {entry.input}
                      <.status_badge status={String.capitalize(entry.status)} />
                      <time
                        datetime={DateTime.to_iso8601(entry.inserted_at)}
                        class="ml-1 text-xs text-base-content/65"
                      >
                        {Calendar.strftime(entry.inserted_at, "%b %d, %H:%M UTC")}
                      </time>
                    </summary>
                    <p class="mt-2 wrap-anywhere whitespace-pre-wrap text-sm">
                      {entry.output || run_summary(entry)}
                    </p>
                    <.tool_trace :if={entry.trace} trace={entry.trace} />
                  </details>
                </div>
              </details>
            </div>
          </section>

          <section
            aria-label="Cell details"
            class="divide-y divide-base-300 border border-base-300 bg-base-100"
          >
            <details class="collapse collapse-arrow">
              <summary class="collapse-title min-h-0 py-3 text-sm font-medium">
                Role and capabilities
              </summary>
              <div class="collapse-content space-y-3 text-sm">
                <p class="wrap-break-word whitespace-pre-wrap">{@role}</p>
                <p>Capabilities: {Enum.join(@cell.capabilities, ", ")}</p>
                <p :if={@cell.skills != []}>Skills: {Enum.join(@cell.skills, ", ")}</p>
              </div>
            </details>
            <details class="collapse collapse-arrow">
              <summary class="collapse-title min-h-0 py-3 text-sm font-medium">Workspace</summary>
              <div class="collapse-content text-sm">
                <p>
                  The workspace is read-only. The inspection tool can read <code>/brief.txt</code>.
                </p>
              </div>
            </details>
            <details class="collapse collapse-arrow">
              <summary class="collapse-title min-h-0 py-3 text-sm font-medium">Cell memory</summary>
              <div class="collapse-content space-y-3 text-sm">
                <ul class="space-y-2">
                  <li :for={memory <- @cell.memories} class="wrap-anywhere">
                    <span class="badge badge-sm badge-ghost mr-1">Definition</span> {memory}
                  </li>
                  <li :for={entry <- @memories} class="wrap-anywhere">
                    <span class="badge badge-sm badge-ghost mr-1">Operator</span> {entry.input}
                  </li>
                </ul>
                <form id="cell-memory" phx-submit="remember" class="flex flex-wrap items-end gap-2">
                  <label class="min-w-36 flex-1">
                    <span class="mb-1 block font-medium">Note</span>
                    <input name="note" type="text" required maxlength="1000" class="input w-full" />
                  </label>
                  <button class="btn">Save note</button>
                </form>
              </div>
            </details>
          </section>
        </div>

        <aside aria-labelledby="chat-title" class="card min-w-0 border border-base-300 bg-base-100">
          <div class="card-body gap-4 p-4">
            <h2
              id="chat-title"
              class="border-b border-base-300 pb-3 text-xs font-semibold tracking-wide text-base-content/75 uppercase"
            >
              Cell chat
            </h2>
            <div
              id={"chat-history-#{@cell.id}"}
              role="log"
              aria-label="Conversation"
              tabindex="0"
              class="flex min-h-28 max-h-[32rem] flex-col-reverse overflow-y-auto pr-2"
            >
              <div class="min-w-0 shrink-0 space-y-3">
                <p :if={@chat == []} class="text-sm text-base-content/70">No messages yet.</p>
                <div :for={entry <- @chat} class="min-w-0 space-y-3">
                  <div class="border-l-2 border-primary/55 bg-primary/7 px-3 py-2.5">
                    <div class="mb-1 text-xs font-semibold text-base-content/75">You</div>
                    <div class="wrap-anywhere whitespace-pre-line text-sm leading-relaxed">
                      {entry.input}
                    </div>
                  </div>
                  <div class="border-l-2 border-base-300 bg-base-200/80 px-3 py-2.5">
                    <div class="mb-1 text-xs font-semibold text-base-content/75">
                      {Path.basename(@cell.id)}
                    </div>
                    <div class="wrap-anywhere whitespace-pre-line text-sm leading-relaxed">
                      {entry.output}
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <form
              id="cell-chat"
              phx-submit="chat"
              class="flex flex-wrap items-end gap-2 border-t border-base-300 pt-3"
            >
              <label class="min-w-36 flex-1">
                <span class="mb-1 block text-sm font-medium">Message</span>
                <input name="message" type="text" required maxlength="1000" class="input w-full" />
              </label>
              <button class="btn btn-outline" phx-disable-with="Sending…">Send</button>
            </form>
          </div>
        </aside>
      </main>
    </div>
    """
  end
end
