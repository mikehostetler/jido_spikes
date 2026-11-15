defmodule JarvisWeb.ChatLive do
  @moduledoc "A LiveView chat client for the Jarvis Jido agent."

  use JarvisWeb, :live_view

  alias Jarvis.Chat
  alias JarvisWeb.Markdown

  @impl true
  def mount(params, _session, socket) do
    conversation_id = Map.get(params, "conversation", "main")
    {:ok, address} = Chat.ensure_conversation(conversation_id)
    {:ok, messages} = Chat.history(address)
    topic = "jarvis:chat:#{conversation_id}"

    if connected?(socket), do: Phoenix.PubSub.subscribe(Jarvis.PubSub, topic)

    {:ok,
     socket
     |> assign(
       page_title: "Jarvis",
       conversation_id: conversation_id,
       address: address,
       topic: topic,
       notices: Jarvis.Chat.ReviewNotice.list(topic),
       messages: messages,
       operation: :ready,
       markdown_parser: nil,
       markdown_ref: nil,
       markdown_started: false,
       error: nil
     )
     |> stream_configure(:markdown, dom_id: fn {id, _document} -> "markdown-#{id}" end)
     |> stream(:markdown, [])}
  end

  @impl true
  def handle_event("send", %{"message" => %{"text" => raw_text}}, socket) do
    text = String.trim(raw_text)

    if text == "" do
      {:noreply, socket}
    else
      submit_chat(socket, text)
    end
  end

  defp submit_chat(socket, text) do
    live_view = self()
    markdown_ref = make_ref()

    {:ok, markdown_parser} =
      Task.Supervisor.start_child(Jarvis.TaskSupervisor, fn ->
        markdown_source(markdown_ref)
        |> Markdown.stream()
        |> Enum.each(fn chunk -> send(live_view, {:markdown_chunk, markdown_ref, chunk}) end)

        send(live_view, {:markdown_done, markdown_ref})
      end)

    case Task.Supervisor.start_child(Jarvis.TaskSupervisor, fn ->
           result =
             Chat.ask(socket.assigns.address, text, socket.assigns.topic,
               memory_namespace: "chat:#{socket.assigns.conversation_id}"
             )

           send(live_view, {:chat_turn_result, result})
         end) do
      {:ok, _task} ->
        optimistic_messages = socket.assigns.messages ++ [%{role: :user, text: text}]

        {:noreply,
         socket
         |> assign(
           messages: optimistic_messages,
           operation: :thinking,
           markdown_parser: markdown_parser,
           markdown_ref: markdown_ref,
           markdown_started: false,
           error: nil
         )
         |> stream(:markdown, [], reset: true)
         |> push_event("clear-composer", %{})}

      {:error, reason} ->
        send(markdown_parser, {:markdown_done, markdown_ref})
        {:noreply, assign(socket, operation: :failed, error: inspect(reason))}
    end
  end

  @impl true
  def handle_info(:review_notice, socket) do
    {:noreply, assign(socket, notices: Jarvis.Chat.ReviewNotice.list(socket.assigns.topic))}
  end

  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.started"}, socket) do
    {:noreply, assign(socket, operation: :streaming)}
  end

  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.chunk"} = signal, socket) do
    text = get_in(signal.data, [:chunk, :text]) || ""
    send_markdown(socket, {:markdown_chunk, socket.assigns.markdown_ref, text})
    {:noreply, socket}
  end

  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.completed"}, socket) do
    finish_markdown(socket)
    {:noreply, socket}
  end

  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.failed"} = signal, socket) do
    finish_markdown(socket)

    {:noreply,
     assign(socket,
       operation: :failed,
       error: inspect(Map.get(signal.data, :reason, :model_failed))
     )}
  end

  def handle_info(
        {:markdown_chunk, ref, {id, document}},
        %{assigns: %{markdown_ref: ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(markdown_started: true)
     |> stream_insert(:markdown, {id, document})}
  end

  def handle_info({:markdown_chunk, _ref, _chunk}, socket), do: {:noreply, socket}

  def handle_info({:markdown_done, ref}, %{assigns: %{markdown_ref: ref}} = socket) do
    {:noreply, assign(socket, markdown_parser: nil)}
  end

  def handle_info({:markdown_done, _ref}, socket), do: {:noreply, socket}

  def handle_info({:chat_turn_result, result}, socket) do
    finish_markdown(socket)

    messages =
      case Chat.history(socket.assigns.address) do
        {:ok, history} -> history
        {:error, _reason} -> socket.assigns.messages
      end

    operation = Chat.operation_state(result)
    error = if operation in [:ready, :committed], do: nil, else: inspect(result)

    {:noreply,
     assign(socket,
       messages: messages,
       operation: operation,
       markdown_parser: nil,
       markdown_started: false,
       error: error
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="jarvis-shell">
      <header class="jarvis-header">
        <div>
          <p class="eyebrow">Jido · Phoenix · Ollama</p>
          <h1>Jarvis</h1>
          <p class="subtitle">A local agent, ready when you are.</p>
        </div>
        <div class="header-actions">
          <.link navigate={~p"/memories"} class="nav-link">Memories</.link>
          <div class="model-chip">
            <span class="status-dot"></span>
            {Chat.model()}
          </div>
        </div>
      </header>

      <main id="conversation" class="conversation" aria-live="polite">
        <section :if={@notices != []} aria-label="Incident review updates">
          <article
            :for={notice <- @notices}
            id={"review-notice-#{notice.id}"}
            class="message message-assistant"
          >
            <div class="message-label">VSM incident review</div>
            <div class="message-body">{notice.text}</div>
          </article>
        </section>
        <section :if={@messages == []} class="empty-state">
          <div class="orb">J</div>
          <h2>What can I help you with?</h2>
          <p>This conversation runs on your local Ollama model.</p>
        </section>

        <article
          :for={{message, index} <- Enum.with_index(@messages)}
          id={"message-#{index}"}
          class={"message message-#{message.role}"}
        >
          <div class="message-label">
            {%{user: "You", assistant: "Jarvis", tool: "Tool result"}[message.role]}
          </div>
          <div :if={message.role == :assistant} class="message-body markdown-body">
            {raw(JarvisWeb.Markdown.render(message.text))}
          </div>
          <div :if={message.role != :assistant} class="message-body">{message.text}</div>
          <details :if={message.role == :tool}>
            <summary>Show tool output</summary>
            <p class="message-body">{message.result}</p>
          </details>
        </article>

        <article
          :if={@operation in [:thinking, :streaming]}
          id="stream"
          class="message message-assistant"
        >
          <div class="message-label">Jarvis</div>
          <div :if={!@markdown_started} class="thinking"><i></i><i></i><i></i></div>
          <div
            :if={@markdown_started}
            id="stream-markdown"
            class="message-body markdown-body"
            phx-update="stream"
          >
            <div
              :for={{dom_id, {_id, document}} <- @streams.markdown}
              id={dom_id}
              class="markdown-block"
            >
              {raw(Markdown.render_document(document))}
            </div>
          </div>
        </article>
      </main>

      <p :if={@error} id="chat-error" class="chat-error">{@error}</p>
      <p class="subtitle">Ask Jarvis to start or pause a review, or ask what the VSM decided.</p>

      <form id="chat-form" phx-submit="send" phx-hook="ChatComposer" class="composer">
        <textarea
          id="message-input"
          name="message[text]"
          placeholder="Message Jarvis…"
          maxlength="8000"
          rows="3"
          required
          disabled={@operation in [:thinking, :streaming]}
        ></textarea>
        <button
          type="submit"
          disabled={@operation in [:thinking, :streaming]}
          aria-label="Send message"
        >
          <span>Send</span>
          <.icon name="hero-arrow-up" class="size-4" />
        </button>
        <span class="composer-hint"><kbd>⌘</kbd><kbd>↵</kbd> to send</span>
      </form>

      <footer>
        Conversation <code>{@conversation_id}</code> · state <strong>{@operation}</strong>
      </footer>
    </div>
    """
  end

  defp markdown_source(ref) do
    Stream.resource(
      fn -> ref end,
      fn ref ->
        receive do
          {:markdown_chunk, ^ref, text} -> {[text], ref}
          {:markdown_done, ^ref} -> {:halt, ref}
        after
          185_000 -> {:halt, ref}
        end
      end,
      fn _ref -> :ok end
    )
  end

  defp send_markdown(%{assigns: %{markdown_parser: parser}}, message) when is_pid(parser) do
    send(parser, message)
  end

  defp send_markdown(_socket, _message), do: :ok

  defp finish_markdown(%{assigns: %{markdown_parser: parser, markdown_ref: ref}})
       when is_pid(parser) do
    send(parser, {:markdown_done, ref})
  end

  defp finish_markdown(_socket), do: :ok
end
