defmodule Kura.Cell.Cognition do
  @moduledoc false

  defmodule Agent do
    use Jido.AI.Agent, name: "kura_cell_cognition"

    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        limits do
          model_calls(2)
          tool_rounds(1)
          tool_calls(1)
          tool_output_bytes(2_048)
          retries(0)
          elapsed_ms(45_000)
        end
      end
    end
  end

  def model(%{cognition: "local"}), do: nil
  def model(_cell), do: Application.get_env(:kura, :cell_model)

  def skill_context(cell) do
    case Application.get_env(:kura, :cell_skill_root) do
      nil ->
        {:ok, ""}

      root ->
        Enum.reduce_while(cell.skills, {:ok, ""}, fn name, {:ok, context} ->
          case Jido.AI.Skill.load([root], name) do
            {:ok, skill} -> {:cont, {:ok, context <> "\n\n" <> skill.instructions}}
            error -> {:halt, error}
          end
        end)
    end
  end

  def pulse(cell, input, instructions, context, tool_policy) do
    case model(cell) do
      nil ->
        %{"status" => "local_demo", "tools" => []}

      model ->
        case reason(cell, input, instructions, model, context, tool_policy) do
          {:ok, reply} ->
            %{
              "model" => model,
              "status" => to_string(reply.status),
              "output" => reply.output,
              "reason" => reply.reason && inspect(reply.reason),
              "tools" => tool_trace(reply)
            }

          {:error, reason} ->
            %{"model" => model, "status" => "error", "reason" => inspect(reason), "tools" => []}
        end
    end
  end

  def chat(cell, message, history, status) do
    case model(cell) do
      nil ->
        {:ok, "#{cell.name} — #{status}\n\n#{cell.role_text}"}

      model ->
        turns = Enum.map_join(history, "\n", &"Operator: #{&1.input}\nCell: #{&1.output}")

        with {:ok, reply} <-
               reason(
                 cell,
                 "Recent conversation:\n#{turns}\n\nCell status:\n#{status}\n\nOperator: #{message}",
                 """
                 Answer the operator using the recorded cell status. A completed work result is the cell's observation.
                 If asked what the work found, summarize that result. If no result is recorded, say so.
                 This is a chat turn. Do not start work, request access to repeat completed work, modify files, or issue commands.
                 """,
                 model,
                 %{},
                 %{requirement: :disabled}
               ) do
          case reply do
            %{status: :completed, output: output} when is_binary(output) -> {:ok, output}
            _ -> {:error, reply.reason || :cognition_incomplete}
          end
        end
    end
  end

  defp reason(cell, input, instructions, model, context, tool_policy) do
    agent = Agent.instantiate!(id: Ash.UUID.generate())

    request =
      Agent.request_signal!(%{
        model: model,
        input: input,
        instructions: instructions <> "\nCell role for context:\n" <> cell.role_text,
        tool_policy: tool_policy,
        stream: context != %{},
        options: model_options(model)
      })

    with {:ok, _, directives} <- Agent.cmd(agent, request, context: context) do
      case Enum.find(directives, &match?(%Jido.Agent.Directive.Reply{}, &1)) do
        %{signal: %{data: reply}} -> {:ok, reply}
        nil -> {:error, :cognition_incomplete}
      end
    end
  end

  defp model_options("openai:gpt-6.1-terra") do
    Map.put(model_options(nil), :reasoning_effort, :none)
  end

  defp model_options(_model) do
    %{max_tokens: 500, receive_timeout: 20_000, total_timeout: 22_000}
  end

  defp tool_trace(reply) do
    Enum.map(reply.tool_attempts, fn attempt ->
      %{
        "id" => attempt.tool_call_id,
        "name" => attempt.tool_name,
        "arguments" => attempt.input,
        "status" => to_string(attempt.status),
        "result" => attempt.output
      }
    end)
  end
end
