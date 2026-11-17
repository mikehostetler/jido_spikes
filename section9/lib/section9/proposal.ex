defmodule Section9.Proposal do
  @moduledoc "Validates one structured cognitive proposal before a ledger commit."

  alias Section9.{BoundedState, RolePolicy}

  def validate(role, value) when is_map(value) do
    with {:ok, narrative} <- required_text(value, "narrative"),
         {:ok, state} <- BoundedState.validate(field(value, "next_state")),
         {:ok, action} <- action(role, field(value, "action")) do
      {:ok,
       %{
         "narrative" => String.slice(narrative, 0, 1_500),
         "next_state" => state,
         "action" => action,
         "audit" => field(value, "audit") || %{}
       }}
    end
  end

  def validate(_role, _value), do: {:error, :invalid_proposal}

  def schema(role) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "narrative" => %{"type" => "string"},
        "next_state" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "focus" => %{"type" => "string"},
            "facts" => %{"type" => "array", "items" => %{"type" => "string"}},
            "next_step" => %{"type" => "string"}
          },
          "required" => BoundedState.fields()
        },
        "action" => %{
          "type" => "object",
          "properties" => %{
            "type" => %{"type" => "string", "enum" => RolePolicy.actions(role)},
            "source" => %{"type" => "string"},
            "reason" => %{"type" => "string"}
          },
          "required" => ["type"]
        }
      },
      "required" => ["narrative", "next_state", "action"]
    }
  end

  defp action(role, action) when is_map(action) do
    type = field(action, "type")

    if is_binary(type) and RolePolicy.allowed?(role, type) do
      {:ok, stringify_keys(action)}
    else
      {:error, {:action_not_allowed, role, type}}
    end
  end

  defp action(role, _), do: {:error, {:invalid_action, role}}

  defp required_text(map, key) do
    case field(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_proposal_field, key}}
    end
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, String.to_atom(key))
  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
