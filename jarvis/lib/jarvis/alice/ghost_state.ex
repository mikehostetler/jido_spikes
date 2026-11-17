defmodule Jarvis.Alice.GhostState do
  @moduledoc "The typed, bounded, replaceable state that continues between pulses."

  @enforce_keys [:situation, :focus, :evidence, :tensions, :intention, :tool_need]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          situation: String.t(),
          focus: String.t(),
          evidence: [String.t()],
          tensions: [String.t()],
          intention: String.t(),
          tool_need: String.t()
        }

  @doc "Creates the first ghost-state from the user observation."
  def initial(thought) when is_binary(thought) do
    %__MODULE__{
      situation: clip(thought, 180),
      focus: "Determine what the new signal means without assuming intent.",
      evidence: ["The initial observation came from the run operator."],
      tensions: ["The signal is salient, but its meaning is unknown."],
      intention: "Observe the strongest available signal and move it one careful step.",
      tool_need: ""
    }
  end

  @doc "Validates and bounds a model-proposed replacement ghost-state."
  def from_map(value) when is_map(value) do
    with {:ok, situation} <- required_string(value, :situation),
         {:ok, focus} <- required_string(value, :focus),
         {:ok, intention} <- required_string(value, :intention),
         {:ok, evidence} <- string_list(value, :evidence),
         {:ok, tensions} <- string_list(value, :tensions),
         {:ok, tool_need} <- optional_string(value, :tool_need) do
      {:ok,
       %__MODULE__{
         situation: clip(situation, 180),
         focus: clip(focus, 160),
         evidence: bound_list(evidence, 3, 100),
         tensions: bound_list(tensions, 3, 100),
         intention: clip(intention, 190),
         tool_need: clip(tool_need, 80)
       }}
    end
  end

  def from_map(_value), do: {:error, :invalid_ghost_state}

  def to_map(%__MODULE__{} = state), do: Map.from_struct(state)

  @doc "Renders the typed state for people, memory search, and model context."
  def render(%__MODULE__{} = state) do
    """
    Situation:
    #{state.situation}

    Focus:
    #{state.focus}

    Evidence:
    #{render_list(state.evidence)}

    Tensions:
    #{render_list(state.tensions)}

    Next intention:
    #{state.intention}

    Pending tool need:
    #{if state.tool_need == "", do: "None", else: state.tool_need}
    """
    |> String.trim()
  end

  defp required_string(map, key) do
    case field(map, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:blank_ghost_field, key}}, else: {:ok, value}

      _other ->
        {:error, {:invalid_ghost_field, key}}
    end
  end

  defp optional_string(map, key) do
    case field(map, key) do
      nil -> {:ok, ""}
      value when is_binary(value) -> {:ok, String.trim(value)}
      _other -> {:error, {:invalid_ghost_field, key}}
    end
  end

  defp string_list(map, key) do
    case field(map, key) do
      values when is_list(values) ->
        if Enum.all?(values, &is_binary/1),
          do: {:ok, Enum.map(values, &String.trim/1)},
          else: {:error, {:invalid_ghost_field, key}}

      _other ->
        {:error, {:invalid_ghost_field, key}}
    end
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp bound_list(values, count, chars) do
    values
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(count)
    |> Enum.map(&clip(&1, chars))
  end

  defp clip(text, maximum) do
    text = String.trim(text)

    if String.length(text) > maximum,
      do: String.slice(text, 0, maximum - 12) <> " [truncated]",
      else: text
  end

  defp render_list([]), do: "- None"
  defp render_list(values), do: Enum.map_join(values, "\n", &("- " <> &1))
end
