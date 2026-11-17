defmodule Section9.Reasoner do
  @moduledoc "Fresh Jido ReAct reasoner used for each local-model pulse."

  use Jido.AI.Agent, name: "section9_reasoner"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      limits do
        model_calls(8)
        tool_rounds(8)
        tool_calls(12)
        tool_output_bytes(65_536)
        retries(0)
        elapsed_ms(120_000)
      end
    end
  end
end

defmodule Section9.Model.JidoReAct do
  @moduledoc "LM Studio adapter that executes one fresh Jido ReAct run."
  @behaviour Section9.Model

  alias Jido.Agent.Directive.Reply

  @impl true
  def propose(role, %{prompt: prompt}, opts) do
    timeout = Application.get_env(:section9, :model_timeout, 120_000)
    model = Keyword.get(opts, :model, Application.fetch_env!(:section9, :model))

    agent =
      Section9.Reasoner.instantiate!(id: "section9-#{role}-#{System.unique_integer([:positive])}")

    request =
      Section9.Reasoner.request_signal!(%{
        input: [%{type: :text, text: prompt.user}],
        instructions: prompt.system,
        model: model,
        stream: true,
        output_schema: nil,
        tool_policy: %{
          requirement: :required,
          visible: ["load_skill", "load_skill_resource"],
          reason: "Section 9 requires the Jido root and command registry before role work."
        },
        options: %{
          receive_timeout: timeout,
          total_timeout: timeout,
          reasoning_effort: :none,
          max_tokens: 2_500
        },
        limits: %{
          model_calls: 8,
          tool_rounds: 8,
          tool_calls: 12,
          tool_output_bytes: 65_536,
          retries: 0,
          elapsed_ms: timeout
        }
      })

    dispatch = stream_dispatch(opts[:on_stream])

    context = %{
      jido_ai_inference_client: Jido.AI.InferenceClient.ReqLLM,
      jido_ai_dispatch: dispatch,
      jido_ai_tool_sources: [Section9.SkillPackage.source()],
      section9_role: role
    }

    with {:ok, _agent, directives} <- Section9.Reasoner.cmd(agent, request, context: context),
         %Reply{signal: %{data: %{status: :completed} = data}} <-
           Enum.find(directives, &match?(%Reply{}, &1)),
         output when not is_nil(output) <- Map.get(data, :output) || Map.get(data, "output"),
         attempts <- Map.get(data, :tool_attempts, Map.get(data, "tool_attempts", [])),
         :ok <- required_skill_attempts(attempts),
         {:ok, decoded} <- decode_output(output) do
      {:ok,
       Map.put(decoded, "audit", %{
         "skill_mode" => "Jido ReAct progressive disclosure",
         "skill_tool_attempts" => attempts
       })}
    else
      nil -> {:error, :missing_jido_reply}
      %Reply{signal: %{data: data}} -> {:error, {:jido_blocked, data}}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_jido_result, other}}
    end
  rescue
    error -> {:error, Exception.format(:error, error, __STACKTRACE__)}
  end

  defp decode_output(output) when is_map(output), do: {:ok, output}
  defp decode_output(output) when is_binary(output), do: Jason.decode(output)

  defp required_skill_attempts(attempts) do
    root? =
      Enum.any?(attempts, fn attempt ->
        field(attempt, :tool_name) == "load_skill" and field(attempt, :status) in [:ok, "ok"] and
          field(field(attempt, :input) || %{}, :name) == "jido"
      end)

    commands? =
      Enum.any?(attempts, fn attempt ->
        field(attempt, :tool_name) == "load_skill_resource" and
          field(attempt, :status) in [:ok, "ok"] and
          field(field(attempt, :input) || %{}, :name) == "jido" and
          field(field(attempt, :input) || %{}, :path) == "references/commands.md"
      end)

    if root? and commands?, do: :ok, else: {:error, :required_jido_skill_not_loaded}
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp stream_dispatch(nil), do: nil

  defp stream_dispatch(callback) do
    {:callback,
     fn signal ->
       text = get_in(signal, [:data, :delta]) || get_in(signal, [:data, "delta"])
       if is_binary(text), do: callback.(text)
     end}
  end
end
