defmodule Jarvis.Alice.ToolPolicy do
  @moduledoc "Classifies and narrows tools for one cognitive pulse."

  alias Jarvis.Alice.{GhostState, Spec}

  @tools %{
    "latest_decision" => :read,
    "start_review" => :write,
    "pause_review" => :write
  }

  def classification(name), do: Map.get(@tools, name)
  def write_tool?(name), do: classification(name) == :write
  def read_tool?(name), do: classification(name) == :read

  def for_pulse(pulse, strategy) do
    text =
      [pulse.directive, pulse.observation, GhostState.render(pulse.ghost_state)]
      |> Enum.join("\n")
      |> String.downcase()

    visible =
      @tools
      |> Map.keys()
      |> Enum.filter(&requested?(&1, text))
      |> maybe_remove_writes(strategy)

    case visible do
      [] ->
        %{
          requirement: :disabled,
          reason: disabled_reason(strategy)
        }

      names ->
        %{
          requirement: :optional,
          visible: names,
          reason: "The directive, observation, or prior intention names this tool need."
        }
    end
  end

  def visible_names(%{visible: names}), do: names
  def visible_names(_policy), do: []

  defp maybe_remove_writes(names, strategy) do
    if Spec.speculative_strategy?(strategy),
      do: Enum.reject(names, &write_tool?/1),
      else: names
  end

  defp disabled_reason(strategy) do
    if Spec.speculative_strategy?(strategy),
      do: "Speculative branches cannot execute write effects.",
      else: "No explicit tool need entered this cognitive cycle."
  end

  defp requested?("latest_decision", text),
    do: contains_any?(text, ["latest decision", "review status", "timer status"])

  defp requested?("start_review", text),
    do: contains_any?(text, ["start review", "start the review", "start review timer"])

  defp requested?("pause_review", text),
    do: contains_any?(text, ["pause review", "pause the review", "pause review timer"])

  defp contains_any?(text, phrases), do: Enum.any?(phrases, &String.contains?(text, &1))
end
