defmodule Jarvis.Alice do
  @moduledoc "The local facade for Alice's bounded cognitive-cycle actor."

  alias Jarvis.Alice.{Character, CognitiveCycle, Effect, GhostState, Spec}

  @max_cycles Spec.max_cycles()

  @doc "Returns the configured local LM Studio model."
  def model, do: Spec.model()

  @doc "Returns Alice's stable Jido.Character identity kernel."
  def character, do: Character.kernel()

  @doc "Returns the rendered identity prompt used for every cognitive cycle."
  def character_prompt, do: Character.system_prompt()

  @doc "Returns the default LiveView form values from the actor specification."
  def default_form, do: Spec.default_form()

  @doc "Creates a new Alice run without contacting the model."
  def new_run(attrs) when is_map(attrs) do
    run_id = "alice-#{Jido.Id.uuid7()}"
    thought = attrs |> field("thought") |> String.trim()
    spec = Spec.default()
    character = spec.character_module.kernel()

    %{
      id: run_id,
      spec: spec,
      memory_namespace: run_id,
      character: character,
      character_prompt: Character.to_system_prompt(character),
      run_directive: run_directive(attrs),
      initial_thought: thought,
      ghost_state: GhostState.initial(thought),
      mode: mode(field(attrs, "mode")),
      turn_limit: turn_limit(field(attrs, "turn_limit")),
      turn: 0,
      status: :ready,
      pending_effects: [],
      effect_receipts: %{}
    }
  end

  @doc "Builds the visible pulse before model work starts."
  def prepare_turn(%{turn: completed} = run) when completed < @max_cycles,
    do: CognitiveCycle.prepare(run)

  @doc "Runs one complete cognitive cycle."
  def run_turn(run, opts \\ [])

  def run_turn(%{turn: completed} = run, opts) when completed < @max_cycles do
    prepared = Keyword.get_lazy(opts, :prepared, fn -> prepare_turn(run) end)
    CognitiveCycle.run(run, prepared, opts)
  end

  def run_turn(_run, _opts), do: {:error, :turn_limit_reached}

  @doc "Dispatches one write effect after the LiveView has committed actor state."
  def dispatch_effect(effect, run), do: Effect.dispatch(effect, run)

  defp field(attrs, key),
    do: Map.get(attrs, key, Map.get(attrs, String.to_existing_atom(key), ""))

  defp run_directive(attrs) do
    case attrs |> field("run_directive") |> String.trim() do
      "" -> Spec.default_directive()
      directive -> directive
    end
  end

  defp mode("automatic"), do: :automatic
  defp mode(_mode), do: :step

  defp turn_limit(value) when is_integer(value), do: value |> max(1) |> min(Spec.max_cycles())

  defp turn_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> turn_limit(number)
      _other -> Spec.max_cycles()
    end
  end

  defp turn_limit(_value), do: Spec.max_cycles()
end
