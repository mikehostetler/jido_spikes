defmodule JidoWorkSystem.Scenarios.Scenario do
  @moduledoc """
  Data for one fixed, deterministic work-system story.

  A step is an atom. A choice step maps each choice name to the beat and run
  status that the choice must produce.
  """

  @enforce_keys [:key, :title, :summary, :learning_point, :steps]
  defstruct [:key, :title, :summary, :learning_point, :steps, audience: :headless]

  @type t :: %__MODULE__{
          key: String.t(),
          title: String.t(),
          summary: String.t(),
          learning_point: String.t(),
          steps: [
            atom()
            | {:beat, atom(), :running | :ended}
            | {:choice, %{String.t() => {atom(), :running | :ended}}}
          ],
          audience: :interactive | :headless
        }

  def next(%__MODULE__{steps: steps}, cursor) do
    case Enum.at(steps, cursor) do
      nil -> :complete
      {:choice, choices} -> {:choice, Map.keys(choices)}
      {:beat, beat, status} -> {:beat, beat, status}
      beat when is_atom(beat) -> {:beat, beat}
    end
  end

  def choose(%__MODULE__{steps: steps}, cursor, choice) do
    case Enum.at(steps, cursor) do
      {:choice, choices} ->
        case Map.fetch(choices, choice) do
          {:ok, {beat, status}} -> {:beat, beat, status}
          :error -> {:error, :invalid_choice}
        end

      _step ->
        {:error, :invalid_choice}
    end
  end
end
