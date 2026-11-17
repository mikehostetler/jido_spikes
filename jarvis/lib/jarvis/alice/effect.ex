defmodule Jarvis.Alice.Effect do
  @moduledoc "A pulse-scoped, idempotent write effect staged by a reasoning tool call."

  @enforce_keys [:id, :pulse_id, :tool_call_id, :tool_name, :params, :status]
  defstruct @enforce_keys

  def from_tool_attempts(pulse, attempts) when is_list(attempts) do
    effects =
      attempts
      |> Enum.filter(&write_attempt?/1)
      |> Enum.map(&from_attempt(pulse, &1))

    cond do
      speculative_write?(pulse.strategy, effects) ->
        {:error, :speculative_strategy_requested_write_effect}

      length(effects) > 1 ->
        {:error, :multiple_write_effects_in_one_pulse}

      true ->
        {:ok, effects}
    end
  end

  def dispatch(%__MODULE__{tool_name: "start_review", params: params} = effect, run) do
    purpose = field(params, :purpose)

    result =
      Jarvis.Chat.StartReview.run(%{purpose: purpose}, %{
        jarvis_chat_topic: "jarvis:alice:#{run.id}"
      })

    receipt(effect, result)
  end

  def dispatch(%__MODULE__{tool_name: "pause_review"} = effect, _run) do
    receipt(effect, Jarvis.Chat.PauseReview.run(%{}, %{}))
  end

  def dispatch(%__MODULE__{} = effect, _run), do: receipt(effect, {:error, :unknown_effect})

  defp from_attempt(pulse, attempt) do
    call_id = field(attempt, :tool_call_id)
    tool_name = field(attempt, :tool_name)
    seed = "#{pulse.run_id}|#{pulse.id}|#{call_id}|#{tool_name}"
    id = :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 24)

    %__MODULE__{
      id: id,
      pulse_id: pulse.id,
      tool_call_id: call_id,
      tool_name: tool_name,
      params: field(attempt, :input) || %{},
      status: :pending
    }
  end

  defp write_attempt?(attempt) do
    field(attempt, :status) in [:ok, "ok"] and
      Jarvis.Alice.ToolPolicy.write_tool?(field(attempt, :tool_name))
  end

  defp speculative_write?(strategy, [_ | _]),
    do: Jarvis.Alice.Spec.speculative_strategy?(strategy)

  defp speculative_write?(_strategy, []), do: false

  defp receipt(effect, {:ok, value}) do
    %{effect_id: effect.id, status: :ok, tool_name: effect.tool_name, value: value}
  end

  defp receipt(effect, {:error, reason}) do
    %{effect_id: effect.id, status: :error, tool_name: effect.tool_name, error: inspect(reason)}
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
