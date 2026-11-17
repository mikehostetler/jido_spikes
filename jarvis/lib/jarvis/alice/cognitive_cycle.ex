defmodule Jarvis.Alice.CognitiveCycle do
  @moduledoc "Runs one complete outer cognitive cycle around a pluggable reasoner."

  alias Jido.Agent.Directive.Reply

  alias Jarvis.Alice.{
    Agent,
    CognitiveProposal,
    Effect,
    GhostState,
    Prompt,
    Pulse,
    Spec,
    ToolPolicy
  }

  alias Jarvis.Memories

  @doc "Observes, recalls, selects a strategy, and renders one visible pulse."
  def prepare(run) do
    number = run.turn + 1
    query = GhostState.render(run.ghost_state)

    memories =
      run.memory_namespace
      |> Memories.recall(query, limit: 3)
      |> Enum.reject(&(&1.content == query))
      |> Enum.take(2)

    strategy = Spec.select_strategy(run.spec, run, number)
    pulse = Pulse.new(run, number, memories, strategy)
    tool_policy = ToolPolicy.for_pulse(pulse, strategy)
    pulse = %{pulse | tool_policy: tool_policy}
    rendered = Prompt.render(pulse)

    %{
      id: pulse.id,
      pulse_id: pulse.id,
      turn: number,
      pulse: pulse,
      model: run.spec.model,
      strategy: strategy,
      character_id: run.character.id,
      character_version: run.character.version,
      character_prompt: run.character_prompt,
      run_directive: run.run_directive,
      request_input: rendered.request_input,
      output_schema: rendered.output_schema,
      input_ghost_state: run.ghost_state,
      input_context: GhostState.render(run.ghost_state),
      model_input: rendered.exact,
      output: "",
      raw_output: nil,
      proposal: nil,
      stream_text: "",
      thinking_text: "",
      next_ghost_state: nil,
      next_context: "Waiting for Alice's cognitive proposal...",
      next_wake: nil,
      tool_policy: tool_policy,
      visible_tools: ToolPolicy.visible_names(tool_policy),
      tool_attempts: [],
      staged_effects: [],
      recalled_memory_ids: Enum.map(memories, & &1.id),
      stored_memory_ids: [],
      stored_memory_id: nil,
      status: :starting,
      model_call: 0,
      stream_events: 0
    }
  end

  @doc "Runs the selected inner reasoner, validates the proposal, and commits memory."
  def run(run, prepared, opts \\ []) do
    stream_to = Keyword.get(opts, :stream_to)
    stream_token = Keyword.get(opts, :stream_token)

    with :ok <- supported_strategy(prepared.strategy),
         {:ok, data} <- run_reasoner(run, prepared, stream_to, stream_token),
         {:ok, proposal} <- CognitiveProposal.from_output(field(data, :output)),
         {:ok, effects} <-
           Effect.from_tool_attempts(prepared.pulse, field(data, :tool_attempts) || []),
         {:ok, memory_ids} <- commit_memory(run, prepared.turn, proposal) do
      {:ok,
       Map.merge(prepared, %{
         output: proposal.narrative,
         raw_output: field(data, :output),
         proposal: proposal,
         stream_text: encoded_output(field(data, :output)),
         next_ghost_state: proposal.next_state,
         next_context: GhostState.render(proposal.next_state),
         next_wake: proposal.next_wake,
         tool_attempts: field(data, :tool_attempts) || [],
         staged_effects: effects,
         stored_memory_ids: memory_ids,
         stored_memory_id: List.first(memory_ids),
         status: :complete
       })}
    end
  rescue
    error -> {:error, Exception.format(:error, error, __STACKTRACE__)}
  end

  defp run_reasoner(run, prepared, stream_to, stream_token) do
    agent = Agent.instantiate!(id: "#{run.id}-pulse-#{prepared.turn}")

    request =
      Agent.request_signal!(%{
        input: prepared.request_input,
        instructions: Prompt.system_instructions(),
        model: run.spec.model,
        stream: true,
        output_schema: prepared.output_schema,
        tool_policy: prepared.tool_policy,
        options: %{
          receive_timeout: run.spec.turn_timeout,
          total_timeout: run.spec.turn_timeout,
          reasoning_effort: :none,
          max_tokens: 1_200
        },
        limits: %{
          model_calls: 8,
          tool_rounds: 2,
          retries: 0,
          elapsed_ms: run.spec.turn_timeout
        }
      })

    context = %{
      jarvis_chat_topic: "jarvis:alice:#{run.id}",
      jido_ai_inference_client:
        Application.get_env(:jido, :ai_inference_client, Jido.AI.InferenceClient.ReqLLM),
      jido_ai_dispatch: stream_dispatch(stream_to, stream_token)
    }

    with {:ok, _next_agent, directives} <- Agent.cmd(agent, request, context: context) do
      reply_data(directives)
    end
  end

  defp reply_data(directives) do
    case Enum.find(directives, &match?(%Reply{}, &1)) do
      %Reply{signal: %{data: %{status: :completed} = data}} -> {:ok, data}
      %Reply{signal: %{data: data}} -> {:error, {:alice_blocked, field(data, :reason)}}
      nil -> {:error, :alice_reply_missing}
    end
  end

  defp commit_memory(run, number, proposal) do
    entries =
      [
        %{
          namespace: run.memory_namespace,
          class: "working",
          title: "Alice pulse #{number} ghost-state",
          content: GhostState.render(proposal.next_state),
          metadata: %{"agent" => "alice", "run_id" => run.id, "pulse" => number}
        }
      ] ++
        (proposal.memories
         |> Enum.with_index(1)
         |> Enum.map(fn {content, index} ->
           %{
             namespace: run.memory_namespace,
             class: "episodic",
             title: "Alice pulse #{number} memory #{index}",
             content: content,
             metadata: %{"agent" => "alice", "run_id" => run.id, "pulse" => number}
           }
         end))

    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, ids} ->
      case Memories.remember(entry) do
        {:ok, memory} -> {:cont, {:ok, ids ++ [memory.id]}}
        {:error, reason} -> {:halt, {:error, {:memory_commit_failed, reason}}}
      end
    end)
  end

  defp supported_strategy(:react), do: :ok
  defp supported_strategy(strategy), do: {:error, {:unsupported_reasoning_strategy, strategy}}

  defp stream_dispatch(nil, _token), do: nil

  defp stream_dispatch(target, token) when is_pid(target) do
    {:pid, target: target, message_format: fn signal -> {:alice_stream, token, signal} end}
  end

  defp encoded_output(output) when is_binary(output), do: output
  defp encoded_output(output) when is_map(output), do: JSON.encode!(output)
  defp encoded_output(output), do: inspect(output)

  defp field(nil, _key), do: nil
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
