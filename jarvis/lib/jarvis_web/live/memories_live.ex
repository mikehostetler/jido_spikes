defmodule JarvisWeb.MemoriesLive do
  @moduledoc "A small CRUD interface for persisted Jarvis memories."

  use JarvisWeb, :live_view

  alias Jarvis.Memories
  alias Jarvis.Memories.Memory

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Memories", editing_id: nil)
     |> assign_memories()
     |> assign_form(Memories.change_memory(%Memory{}))}
  end

  @impl true
  def handle_event("validate", %{"memory" => params}, socket) do
    memory = editing_memory(socket)

    changeset =
      memory
      |> Memories.change_memory(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"memory" => params}, socket) do
    result =
      case socket.assigns.editing_id do
        nil -> Memories.remember(params)
        id -> id |> Memories.get_memory!() |> Memories.supersede(params)
      end

    case result do
      {:ok, _memory} ->
        {:noreply,
         socket
         |> put_flash(:info, memory_saved_message(socket.assigns.editing_id))
         |> assign(editing_id: nil)
         |> assign_memories()
         |> assign_form(Memories.change_memory(%Memory{}))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    memory = Memories.get_memory!(id)

    {:noreply,
     socket
     |> assign(editing_id: memory.id)
     |> assign_form(Memories.change_memory(memory))}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(editing_id: nil)
     |> assign_form(Memories.change_memory(%Memory{}))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    memory = Memories.get_memory!(id)
    {:ok, _memory} = Memories.forget(memory)

    socket =
      if socket.assigns.editing_id == memory.id do
        socket
        |> assign(editing_id: nil)
        |> assign_form(Memories.change_memory(%Memory{}))
      else
        socket
      end

    {:noreply,
     socket
     |> put_flash(:info, "Memory deleted")
     |> assign_memories()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="memories-shell">
      <JarvisWeb.Layouts.flash_group flash={@flash} />

      <header class="memories-header">
        <div>
          <p class="eyebrow">Jarvis knowledge store</p>
          <h1>Memories</h1>
          <p class="subtitle">Small facts and notes stored in SQLite.</p>
        </div>
        <.link navigate={~p"/"} class="nav-link">Back to chat</.link>
      </header>

      <section class="memory-editor">
        <div class="section-heading">
          <h2>{if @editing_id, do: "Edit memory", else: "New memory"}</h2>
          <button :if={@editing_id} type="button" phx-click="cancel" class="text-button">
            Cancel
          </button>
        </div>

        <.form for={@form} id="memory-form" phx-change="validate" phx-submit="save">
          <div class="memory-fields-row">
            <div>
              <label for={@form[:namespace].id}>Namespace</label>
              <input
                type="text"
                id={@form[:namespace].id}
                name={@form[:namespace].name}
                value={@form[:namespace].value}
                maxlength="200"
                required
              />
            </div>
            <div>
              <label for={@form[:class].id}>Class</label>
              <select id={@form[:class].id} name={@form[:class].name}>
                <option
                  :for={class <- Memories.classes()}
                  value={class}
                  selected={to_string(@form[:class].value) == class}
                >
                  {class}
                </option>
              </select>
            </div>
          </div>

          <label for={@form[:title].id}>Title</label>
          <input
            type="text"
            id={@form[:title].id}
            name={@form[:title].name}
            value={@form[:title].value}
            maxlength="200"
            placeholder="What should Jarvis remember?"
            required
          />
          <p :for={error <- @form[:title].errors} class="field-error">
            {translate_error(error)}
          </p>

          <label for={@form[:content].id}>Content</label>
          <textarea
            id={@form[:content].id}
            name={@form[:content].name}
            maxlength="50000"
            rows="7"
            placeholder="Markdown is supported."
            required
          >{@form[:content].value}</textarea>
          <p :for={error <- @form[:content].errors} class="field-error">
            {translate_error(error)}
          </p>

          <button type="submit" class="primary-button">
            {if @editing_id, do: "Save changes", else: "Create memory"}
          </button>
        </.form>
      </section>

      <section class="memory-list-section">
        <div class="section-heading">
          <h2>Stored memories</h2>
          <span class="memory-count">{length(@memories)}</span>
        </div>

        <div :if={@memories == []} id="empty-memories" class="memory-empty">
          No memories yet. Add the first one above.
        </div>

        <div id="memories" class="memory-grid">
          <article :for={memory <- @memories} id={"memory-#{memory.id}"} class="memory-card">
            <header>
              <div>
                <h3>{memory.title}</h3>
                <span class="memory-type">{memory.namespace} · {memory.class}</span>
              </div>
              <time datetime={DateTime.to_iso8601(memory.updated_at)}>
                {Calendar.strftime(memory.updated_at, "%b %-d, %Y · %-I:%M %p")}
              </time>
            </header>

            <div class="memory-content markdown-body">
              {raw(JarvisWeb.Markdown.render(memory.content))}
            </div>

            <footer class="memory-actions">
              <button type="button" phx-click="edit" phx-value-id={memory.id}>Edit</button>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={memory.id}
                data-confirm="Delete this memory?"
                class="danger-button"
              >
                Delete
              </button>
            </footer>
          </article>
        </div>
      </section>
    </div>
    """
  end

  defp assign_memories(socket), do: assign(socket, :memories, Memories.list_memories())

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :memory))
  end

  defp editing_memory(%{assigns: %{editing_id: nil}}), do: %Memory{}
  defp editing_memory(%{assigns: %{editing_id: id}}), do: Memories.get_memory!(id)

  defp memory_saved_message(nil), do: "Memory created"
  defp memory_saved_message(_id), do: "Memory updated"
end
