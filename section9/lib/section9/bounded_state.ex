defmodule Section9.BoundedState do
  @moduledoc "A complete, bounded replacement state for one persistent actor."

  @fields ~w(focus facts next_step)

  def initial(role) do
    %{
      "focus" => "Wait for the next #{role} duty.",
      "facts" => [],
      "next_step" => "Inspect committed ledger facts."
    }
  end

  def validate(value) when is_map(value) do
    with {:ok, focus} <- text(value, "focus", 240),
         {:ok, facts} <- facts(value),
         {:ok, next_step} <- text(value, "next_step", 240) do
      {:ok, %{"focus" => focus, "facts" => facts, "next_step" => next_step}}
    end
  end

  def validate(_), do: {:error, :invalid_state}

  defp text(map, key, max) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      value when is_binary(value) and value != "" -> {:ok, String.slice(value, 0, max)}
      _ -> {:error, {:invalid_state_field, key}}
    end
  end

  defp facts(map) do
    case Map.get(map, "facts") || Map.get(map, :facts) do
      values when is_list(values) ->
        if Enum.all?(values, &is_binary/1) do
          {:ok, values |> Enum.take(5) |> Enum.map(&String.slice(&1, 0, 180))}
        else
          {:error, {:invalid_state_field, "facts"}}
        end

      _ ->
        {:error, {:invalid_state_field, "facts"}}
    end
  end

  def fields, do: @fields
end
