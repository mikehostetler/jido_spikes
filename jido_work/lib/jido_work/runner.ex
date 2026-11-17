defmodule JidoWork.Runner do
  @moduledoc "Runs one Jido Work request through the v3 ReAct agent."

  alias Jido.Agent.Directive.Reply

  alias JidoWork.{
    FullSkillSource,
    HarnessSource,
    LMStudioClient,
    OfflineClient,
    Workspace,
    WorkAgent
  }

  def run(prompt, mode, model_id) when mode in [:lmstudio, :offline] do
    :ok = configure_skill_gate(prompt)

    sources = [FullSkillSource.source([skills_root()]), HarnessSource.source()]

    context = %{
      jido_ai_tool_sources: sources,
      jido_ai_inference_client: inference_client(mode)
    }

    execution = fn ->
      agent = WorkAgent.instantiate!(id: "jido-work-#{System.unique_integer([:positive])}")
      request = WorkAgent.request_signal!(%{input: prompt})

      case WorkAgent.cmd(agent, request, context: context) do
        {:ok, _next_agent, directives} -> result_from_directives(directives, mode)
        {:error, reason} -> {:error, %{status: :failed, reason: inspect(reason)}}
      end
    end

    case mode do
      :lmstudio -> LMStudioClient.with_model(model_id, execution)
      :offline -> OfflineClient.with_scenario(scenario(prompt), execution)
    end
  rescue
    error -> {:error, %{status: :failed, reason: Exception.format(:error, error, __STACKTRACE__)}}
  end

  def skills_root, do: Application.app_dir(:jido_work, "priv/skills")

  defp result_from_directives(directives, mode) do
    case Enum.find(directives, &match?(%Reply{}, &1)) do
      %Reply{signal: %{data: data}} ->
        {:ok,
         %{
           status: Map.get(data, :status, Map.get(data, "status", :completed)),
           output: Map.get(data, :output, Map.get(data, "output", "")),
           reason: Map.get(data, :reason, Map.get(data, "reason")),
           mode: mode,
           workspace: Workspace.snapshot()
         }}

      nil ->
        {:error, %{status: :failed, reason: "The ReAct run returned no Reply directive."}}
    end
  end

  defp inference_client(:lmstudio), do: LMStudioClient
  defp inference_client(:offline), do: OfflineClient

  defp scenario(prompt) do
    if String.contains?(String.downcase(prompt), "$tutor"), do: :tutor, else: :jido
  end

  defp configure_skill_gate(prompt) do
    case String.downcase(String.trim(prompt)) do
      "$jido" <> _rest -> Workspace.require_skill("jido", ["references/commands.md"])
      "$tutor" <> _rest -> Workspace.require_skill("tutor", ["references/curriculum.md"])
      _other -> :ok
    end
  end
end
