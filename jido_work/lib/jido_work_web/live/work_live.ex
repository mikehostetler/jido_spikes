defmodule JidoWorkWeb.WorkLive do
  use JidoWorkWeb, :live_view

  alias JidoWork.{FullSkillSource, LMStudioClient, Runner, Workspace}

  @jido_prompt "$jido Diagnose the VFS calculator defect, repair it with the confined tools, and verify it through Jido Shell. Do not commit."
  @tutor_prompt "$tutor Teach me how to define a clear outcome and check for the VFS calculator task."

  @impl true
  def mount(_params, _session, socket) do
    health = LMStudioClient.health()
    model = List.first(health.models) || System.get_env("LMSTUDIO_MODEL") || ""
    mode = if health.status == :online, do: "lmstudio", else: "offline"
    {:ok, skills} = FullSkillSource.catalog([Runner.skills_root()])

    socket =
      socket
      |> assign(:page_title, "Jido Work")
      |> assign(:health, health)
      |> assign(:skills, skills)
      |> assign(:running, false)
      |> assign(:result, nil)
      |> assign(:error, nil)
      |> assign(:form, run_form(@jido_prompt, mode, model))
      |> refresh_workspace()

    {:ok, socket}
  end

  @impl true
  def handle_event("preset", %{"skill" => skill}, socket) do
    prompt = if skill == "tutor", do: @tutor_prompt, else: @jido_prompt
    params = socket.assigns.form.params |> Map.put("prompt", prompt)
    {:noreply, assign(socket, :form, to_form(params, as: :run))}
  end

  def handle_event("reset", _params, socket) do
    :ok = Workspace.reset()
    {:noreply, socket |> assign(:result, nil) |> assign(:error, nil) |> refresh_workspace()}
  end

  def handle_event("refresh_lm", _params, socket) do
    health = LMStudioClient.health()
    params = socket.assigns.form.params
    model = Map.get(params, "model", "")
    next_model = if model == "", do: List.first(health.models) || "", else: model

    {:noreply,
     socket
     |> assign(:health, health)
     |> assign(:form, to_form(Map.put(params, "model", next_model), as: :run))}
  end

  def handle_event("run", %{"run" => params}, socket) do
    prompt = String.trim(Map.get(params, "prompt", ""))
    model = String.trim(Map.get(params, "model", ""))
    mode = parse_mode(Map.get(params, "mode", "offline"))

    cond do
      prompt == "" ->
        {:noreply, assign(socket, :error, "Enter a request.")}

      mode == :lmstudio and model == "" ->
        {:noreply, assign(socket, :error, "Enter the LM Studio model ID.")}

      true ->
        :ok = Workspace.reset()

        socket =
          socket
          |> assign(:running, true)
          |> assign(:result, nil)
          |> assign(:error, nil)
          |> assign(:form, to_form(params, as: :run))
          |> refresh_workspace()
          |> start_async(:agent_run, fn -> Runner.run(prompt, mode, model) end)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:agent_run, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:running, false)
     |> assign(:result, result)
     |> refresh_workspace()}
  end

  def handle_async(:agent_run, {:ok, {:error, result}}, socket) do
    {:noreply,
     socket
     |> assign(:running, false)
     |> assign(:error, result.reason)
     |> refresh_workspace()}
  end

  def handle_async(:agent_run, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:running, false)
     |> assign(:error, "Agent task exited: #{inspect(reason)}")
     |> refresh_workspace()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="jido-work" data-testid="jido-work-page" class="space-y-6">
        <header class="rounded-3xl bg-neutral px-6 py-8 text-neutral-content shadow-xl sm:px-10">
          <div class="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div class="max-w-3xl space-y-3">
              <p class="font-mono text-xs uppercase tracking-[0.28em] text-primary">
                Technical feasibility spike
              </p>
              <h1 class="text-4xl font-bold tracking-tight sm:text-5xl">Jido Work</h1>
              <p class="text-base leading-7 text-neutral-content/75 sm:text-lg">
                Jido v3 ReAct with complete Agent Skills packages, progressive resource loading,
                local LM Studio inference, Jido VFS storage, and Jido Shell tools.
              </p>
            </div>
            <div class="flex flex-wrap gap-2 text-xs font-mono">
              <span class="badge badge-primary badge-lg">Jido 3.0.0-beta.2</span>
              <span class="badge badge-outline badge-lg">ReAct</span>
              <span class="badge badge-outline badge-lg">183 skill files</span>
            </div>
          </div>
        </header>

        <div class="grid gap-6 xl:grid-cols-[minmax(0,1.5fr)_minmax(320px,0.8fr)]">
          <section class="card bg-base-100 shadow-lg" data-testid="run-panel">
            <div class="card-body gap-5">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 class="card-title text-2xl">Run the agent</h2>
                  <p class="mt-1 text-sm text-base-content/65">
                    Use a real local model or the repeatable QA client.
                  </p>
                </div>
                <div class="flex gap-2">
                  <button class="btn btn-sm btn-outline" phx-click="preset" phx-value-skill="jido">$jido task</button>
                  <button class="btn btn-sm btn-outline" phx-click="preset" phx-value-skill="tutor">$tutor task</button>
                </div>
              </div>

              <form id="agent-run-form" phx-submit="run" class="space-y-4">
                <div class="grid gap-4 sm:grid-cols-2">
                  <label class="form-control">
                    <span class="label-text mb-2 font-semibold">Inference path</span>
                    <select
                      name="run[mode]"
                      class="select select-bordered w-full"
                      data-testid="mode-select"
                    >
                      <option value="offline" selected={@form.params["mode"] == "offline"}>
                        Deterministic QA
                      </option>
                      <option value="lmstudio" selected={@form.params["mode"] == "lmstudio"}>
                        LM Studio
                      </option>
                    </select>
                  </label>
                  <label class="form-control">
                    <span class="label-text mb-2 font-semibold">LM Studio model ID</span>
                    <input
                      name="run[model]"
                      value={@form.params["model"]}
                      class="input input-bordered w-full font-mono text-sm"
                      placeholder="qwen3.8-27b-mlx"
                      data-testid="model-input"
                    />
                  </label>
                </div>

                <label class="form-control">
                  <span class="label-text mb-2 font-semibold">Request</span>
                  <textarea
                    name="run[prompt]"
                    class="textarea textarea-bordered min-h-36 w-full font-mono text-sm leading-6"
                    data-testid="prompt-input"
                  >{@form.params["prompt"]}</textarea>
                </label>

                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div class="flex items-center gap-2 text-sm" data-testid="lmstudio-status">
                    <span class={health_dot(@health.status)}></span>
                    <span>{@health.message}</span>
                    <button type="button" class="link link-primary" phx-click="refresh_lm">Refresh</button>
                  </div>
                  <div class="flex gap-2">
                    <button type="button" class="btn btn-ghost" phx-click="reset">Reset VFS</button>
                    <button
                      class="btn btn-primary min-w-36"
                      disabled={@running}
                      data-testid="run-button"
                    >
                      <span :if={@running} class="loading loading-spinner loading-sm"></span>
                      {if @running, do: "Running ReAct", else: "Run ReAct"}
                    </button>
                  </div>
                </div>
              </form>

              <div :if={@error} class="alert alert-error" data-testid="run-error">
                <span class="font-mono text-sm whitespace-pre-wrap">{@error}</span>
              </div>

              <div
                :if={@result}
                class="rounded-2xl border border-primary/30 bg-primary/10 p-5"
                data-testid="agent-result"
              >
                <div class="mb-3 flex items-center justify-between gap-3">
                  <h3 class="font-semibold text-primary">{result_title(@result.status)}</h3>
                  <div class="flex gap-2">
                    <span class="badge badge-outline">{@result.status}</span>
                    <span class="badge badge-primary badge-outline">{@result.mode}</span>
                  </div>
                </div>
                <pre class="whitespace-pre-wrap font-sans text-sm leading-6 text-base-content">{result_text(@result)}</pre>
              </div>
            </div>
          </section>

          <aside class="space-y-6">
            <section class="card bg-base-100 shadow-lg" data-testid="skills-panel">
              <div class="card-body">
                <h2 class="card-title">Skill packages</h2>
                <p class="text-sm text-base-content/60">
                  Root loading uses Jido. Nested resources use the spike adapter.
                </p>
                <div class="mt-2 space-y-3">
                  <div
                    :for={skill <- @skills}
                    class="rounded-2xl border border-base-300 p-4"
                    data-testid={"skill-#{skill.name}"}
                  >
                    <div class="flex items-center justify-between gap-3">
                      <span class="font-mono font-bold">${skill.name}</span>
                      <span class="badge badge-ghost">{skill.resource_count} resources</span>
                    </div>
                    <p class="mt-2 line-clamp-3 text-xs leading-5 text-base-content/65">
                      {skill.description}
                    </p>
                  </div>
                </div>
                <div class="mt-2 rounded-xl bg-warning/10 p-3 text-xs leading-5 text-warning-content">
                  Native `Jido.AI.Skill` stops at `SKILL.md`. `FullSkillSource` adds the resource manifest and safe loader. The ReAct tool-result budget is 64 KiB, so the full Jido root skill reaches the model.
                </div>
              </div>
            </section>

            <section class="card bg-base-100 shadow-lg">
              <div class="card-body">
                <h2 class="card-title text-base">Candidate pins</h2>
                <dl class="space-y-3 font-mono text-xs">
                  <div>
                    <dt class="text-base-content/50">Jido release/v3</dt><dd class="break-all">
                      ec96da6015b
                    </dd>
                  </div>
                  <div>
                    <dt class="text-base-content/50">agentjido/skills</dt><dd class="break-all">
                      a71868c975d1
                    </dd>
                  </div>
                  <div>
                    <dt class="text-base-content/50">Jido VFS</dt><dd>
                      1.0.1 · Hex
                    </dd>
                  </div>
                  <div>
                    <dt class="text-base-content/50">Jido Shell</dt><dd class="break-all">
                      3c585dd89037
                    </dd>
                  </div>
                  <div>
                    <dt class="text-base-content/50">Skill tool boundary</dt><dd>
                      load_skill + load_skill_resource
                    </dd>
                  </div>
                  <div>
                    <dt class="text-base-content/50">ReAct tool rounds</dt><dd>
                      8 maximum · core follow-up
                    </dd>
                  </div>
                </dl>
              </div>
            </section>
          </aside>
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <section class="card bg-base-100 shadow-lg" data-testid="activity-panel">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <h2 class="card-title">Tool activity</h2>
                <span class="badge badge-neutral">{length(@workspace.events)} calls</span>
              </div>
              <div class="mt-2 max-h-[34rem] space-y-3 overflow-auto">
                <p :if={@workspace.events == []} class="py-8 text-center text-sm text-base-content/50">
                  Run a task to see skill and coding tool calls.
                </p>
                <article
                  :for={event <- @workspace.events}
                  class="rounded-xl border border-base-300 p-3"
                  data-testid={"event-#{event.tool}"}
                >
                  <div class="flex items-center justify-between gap-3">
                    <code class="font-bold text-primary">{event.tool}</code>
                    <time class="text-[10px] text-base-content/45">{event.at}</time>
                  </div>
                  <pre class="mt-2 whitespace-pre-wrap text-xs leading-5 text-base-content/70">{inspect(event.arguments, pretty: true, limit: 12)}</pre>
                  <pre class="mt-2 whitespace-pre-wrap rounded-lg bg-base-200 p-2 text-[11px] leading-5">{inspect(event.result, pretty: true, limit: 12)}</pre>
                </article>
              </div>
            </div>
          </section>

          <section class="card bg-base-100 shadow-lg" data-testid="workspace-panel">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <h2 class="card-title">Jido workspace</h2>
                <span class="badge badge-outline">VFS + Shell</span>
              </div>
              <p class="text-sm text-base-content/60">
                {@workspace.runtime.filesystem} · {@workspace.runtime.shell}. Host files stay untouched.
              </p>
              <p class="text-xs font-mono text-base-content/60" data-testid="skill-gate-status">
                {skill_gate_text(@workspace.skill_gate)}
              </p>
              <div class="mt-2 max-h-[34rem] space-y-3 overflow-auto">
                <details
                  :for={{path, content} <- @workspace.files}
                  class="collapse collapse-arrow border border-base-300 bg-base-100"
                  open={path == "lib/calculator.ex"}
                >
                  <summary class="collapse-title min-h-0 py-3 font-mono text-sm font-semibold">
                    {path}
                  </summary>
                  <div class="collapse-content">
                    <pre class="overflow-auto rounded-lg bg-neutral p-3 text-xs leading-5 text-neutral-content">{content}</pre>
                  </div>
                </details>
              </div>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp run_form(prompt, mode, model),
    do: to_form(%{"prompt" => prompt, "mode" => mode, "model" => model}, as: :run)

  defp refresh_workspace(socket) do
    snapshot = Workspace.snapshot()
    assign(socket, :workspace, %{snapshot | files: Enum.sort_by(snapshot.files, &elem(&1, 0))})
  end

  defp parse_mode("lmstudio"), do: :lmstudio
  defp parse_mode(_mode), do: :offline

  defp health_dot(:online), do: "inline-block size-2 rounded-full bg-success"
  defp health_dot(_status), do: "inline-block size-2 rounded-full bg-warning"

  defp result_title(:completed), do: "ReAct completed"
  defp result_title(:blocked), do: "ReAct blocked"
  defp result_title(:failed), do: "ReAct failed"
  defp result_title(status), do: "ReAct #{status}"

  defp result_text(%{output: output}) when is_binary(output) and output != "", do: output
  defp result_text(%{reason: reason}) when is_binary(reason), do: reason
  defp result_text(_result), do: "The run returned no output or reason."

  defp skill_gate_text(%{status: :not_required}), do: "Skill gate: not required"

  defp skill_gate_text(%{status: :satisfied, name: name}),
    do: "Skill gate: $#{name} root and required route resource loaded"

  defp skill_gate_text(%{status: :waiting, name: name, missing_resources: missing}),
    do: "Skill gate: waiting for $#{name} #{Enum.join(missing, ", ")}"
end
