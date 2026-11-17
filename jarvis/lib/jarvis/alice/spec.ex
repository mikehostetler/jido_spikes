defmodule Jarvis.Alice.Spec do
  @moduledoc "The single static specification for Alice's cognitive cycle."

  alias Jarvis.Alice.Character

  @max_cycles 100
  @turn_timeout 600_000
  @model "lmstudio:lfm3-1.7b"
  @default_directive """
  Maintain a quiet background watch. In each cognitive cycle, find the signal
  that can most change the current decision. Move one concern forward without
  inventing evidence or changing who you are.
  """

  @enforce_keys [:character_module, :model, :max_cycles, :turn_timeout]
  defstruct @enforce_keys

  @type strategy :: :react | :tree_of_thoughts | :graph_of_thoughts
  @type t :: %__MODULE__{
          character_module: module(),
          model: String.t(),
          max_cycles: pos_integer(),
          turn_timeout: pos_integer()
        }

  @doc "Returns the typed version-one specification for a new run."
  def default do
    %__MODULE__{
      character_module: Character,
      model: System.get_env("ALICE_MODEL", @model),
      max_cycles: @max_cycles,
      turn_timeout: @turn_timeout
    }
  end

  def character_module, do: default().character_module
  def model, do: default().model
  def max_cycles, do: default().max_cycles
  def turn_timeout, do: default().turn_timeout
  def default_directive, do: String.trim(@default_directive)

  def default_form do
    %{
      "run_directive" => default_directive(),
      "thought" => "",
      "mode" => "step",
      "turn_limit" => Integer.to_string(@max_cycles)
    }
  end

  @doc "Selects the pluggable inner strategy for one pulse."
  @spec select_strategy(t(), map(), pos_integer()) :: strategy()
  def select_strategy(%__MODULE__{}, _run, _pulse_number), do: :react

  @doc "Identifies strategies whose branches must remain free of write effects."
  def speculative_strategy?(strategy),
    do: strategy in [:tree_of_thoughts, :graph_of_thoughts]
end
