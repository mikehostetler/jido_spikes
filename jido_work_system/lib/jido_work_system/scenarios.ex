defmodule JidoWorkSystem.Scenarios do
  @moduledoc """
  Registry for fixed work-system scenarios.
  """

  alias JidoWorkSystem.Scenarios.{HeadlessCatalog, MissingRiskSection, StraightThroughRelease}

  @interactive_modules [StraightThroughRelease, MissingRiskSection]

  def list, do: list(:interactive)

  def list(:interactive), do: Enum.map(@interactive_modules, & &1.definition())
  def list(:headless), do: HeadlessCatalog.list()
  def list(:all), do: list(:interactive) ++ list(:headless)

  def fetch(key) when is_binary(key) do
    case Enum.find(list(:all), &(&1.key == key)) do
      nil -> {:error, :unknown_scenario}
      definition -> {:ok, definition}
    end
  end

  def fetch(_key), do: {:error, :unknown_scenario}
end
