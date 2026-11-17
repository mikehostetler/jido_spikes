defmodule Jarvis.Alice.CognitiveProposal do
  @moduledoc "The typed model proposal that must pass validation before commit."

  alias Jarvis.Alice.GhostState

  @enforce_keys [:narrative, :next_state, :memories, :next_wake]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          narrative: String.t(),
          next_state: GhostState.t(),
          memories: [String.t()],
          next_wake: :continue | :wait | :stop
        }

  def from_output(output) when is_binary(output) do
    with {:ok, decoded} <- JSON.decode(output), do: from_output(decoded)
  end

  def from_output(output) when is_map(output) do
    with {:ok, narrative} <- required_string(output, :narrative),
         {:ok, next_state} <- GhostState.from_map(field(output, :next_state)),
         {:ok, memories} <- memories(field(output, :memories)),
         {:ok, next_wake} <- next_wake(field(output, :next_wake)) do
      {:ok,
       %__MODULE__{
         narrative: clip(narrative, 2_400),
         next_state: next_state,
         memories: memories,
         next_wake: next_wake
       }}
    end
  end

  def from_output(_output), do: {:error, :invalid_cognitive_proposal}

  def json_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "narrative" => %{"type" => "string"},
        "next_state" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "situation" => %{"type" => "string"},
            "focus" => %{"type" => "string"},
            "evidence" => %{"type" => "array", "items" => %{"type" => "string"}},
            "tensions" => %{"type" => "array", "items" => %{"type" => "string"}},
            "intention" => %{"type" => "string"},
            "tool_need" => %{"type" => "string"}
          },
          "required" => [
            "situation",
            "focus",
            "evidence",
            "tensions",
            "intention",
            "tool_need"
          ]
        },
        "memories" => %{"type" => "array", "items" => %{"type" => "string"}},
        "next_wake" => %{"type" => "string", "enum" => ["continue", "wait", "stop"]}
      },
      "required" => ["narrative", "next_state", "memories", "next_wake"]
    }
  end

  defp required_string(map, key) do
    case field(map, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:invalid_proposal_field, key}}, else: {:ok, value}

      _other ->
        {:error, {:invalid_proposal_field, key}}
    end
  end

  defp memories(values) when is_list(values) do
    if Enum.all?(values, &is_binary/1) do
      {:ok,
       values
       |> Enum.map(&String.trim/1)
       |> Enum.reject(&(&1 == ""))
       |> Enum.take(2)
       |> Enum.map(&clip(&1, 240))}
    else
      {:error, {:invalid_proposal_field, :memories}}
    end
  end

  defp memories(_value), do: {:error, {:invalid_proposal_field, :memories}}

  defp next_wake(value) when value in ["continue", :continue], do: {:ok, :continue}
  defp next_wake(value) when value in ["wait", :wait], do: {:ok, :wait}
  defp next_wake(value) when value in ["stop", :stop], do: {:ok, :stop}
  defp next_wake(_value), do: {:error, {:invalid_proposal_field, :next_wake}}

  defp field(nil, _key), do: nil
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp clip(text, maximum) do
    if String.length(text) > maximum,
      do: String.slice(text, 0, maximum - 12) <> " [truncated]",
      else: text
  end
end
