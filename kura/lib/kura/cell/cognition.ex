defmodule Kura.Cell.Cognition do
  @moduledoc false

  alias Jido.Holon.Cognition

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
        Cognition.trace(
          model,
          input,
          with_role(instructions, cell),
          context,
          tool_policy,
          model_options(model)
        )
    end
  end

  def chat(cell, message, history, status) do
    case model(cell) do
      nil ->
        {:ok, "#{cell.name} — #{status}\n\n#{cell.role_text}"}

      model ->
        turns = Enum.map_join(history, "\n", &"Operator: #{&1.input}\nCell: #{&1.output}")

        with {:ok, reply} <-
               Cognition.reason(
                 model,
                 "Recent conversation:\n#{turns}\n\nCell status:\n#{status}\n\nOperator: #{message}",
                 with_role(
                   """
                   Answer the operator using the recorded cell status. A completed work result is the cell's observation.
                   If asked what the work found, summarize that result. If no result is recorded, say so.
                   This is a chat turn. Do not start work, request access to repeat completed work, modify files, or issue commands.
                   """,
                   cell
                 ),
                 %{},
                 %{requirement: :disabled},
                 model_options(model)
               ) do
          case reply do
            %{status: :completed, output: output} when is_binary(output) -> {:ok, output}
            _ -> {:error, reply.reason || :cognition_incomplete}
          end
        end
    end
  end

  defp with_role(instructions, cell),
    do: instructions <> "\nCell role for context:\n" <> cell.role_text

  defp model_options("openai:gpt-6.1-terra") do
    Map.put(model_options(nil), :reasoning_effort, :none)
  end

  defp model_options(_model) do
    %{max_tokens: 500, receive_timeout: 20_000, total_timeout: 22_000}
  end
end
