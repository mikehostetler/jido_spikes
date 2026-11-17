defmodule JidoWork.OfflineClient do
  @moduledoc "Deterministic inference for repeatable browser and test checks."

  @behaviour Jido.AI.InferenceClient

  def with_scenario(scenario, fun) when scenario in [:jido, :tutor] and is_function(fun, 0) do
    :ok = JidoWork.Workspace.set_script_scenario(scenario)
    fun.()
  end

  @impl true
  def generate_text(model, context, _options) do
    {scenario, step} = JidoWork.Workspace.next_script_step()

    case scripted_step(scenario, step) do
      {:tool, name, arguments} -> tool_response(model, context, step, name, arguments)
      {:final, text} -> final_response(model, context, step, text)
    end
  end

  @impl true
  def evaluation_models, do: []

  @handled [generate_text: 3, evaluation_models: 0]

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      {name, arity} not in @handled do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
      do: {:error, :not_supported}
  end

  defp scripted_step(:jido, 0), do: {:tool, "load_skill", %{name: "jido"}}

  defp scripted_step(:jido, 1),
    do: {:tool, "load_skill_resource", %{name: "jido", path: "references/commands.md"}}

  defp scripted_step(:jido, 2), do: {:tool, "read_file", %{path: "lib/calculator.ex"}}

  defp scripted_step(:jido, 3) do
    {:tool, "edit_file",
     %{path: "lib/calculator.ex", old_text: "left - right", new_text: "left + right"}}
  end

  defp scripted_step(:jido, 4),
    do: {:tool, "run_shell", %{command: "cat /lib/calculator.ex"}}

  defp scripted_step(:jido, _step) do
    {:final,
     """
     Jido | Sequence: investigate VFS defect → produce checked VFS edit → verify through Jido Shell | Authority: local-write — confined in-memory VFS only; no commit or push.

     The `jido` skill and its routing registry loaded through progressive disclosure. I changed the VFS calculator from subtraction to addition. Jido Shell read the changed file back from the same Jido VFS filesystem. No host file changed.
     """}
  end

  defp scripted_step(:tutor, 0), do: {:tool, "load_skill", %{name: "tutor"}}

  defp scripted_step(:tutor, 1),
    do: {:tool, "load_skill_resource", %{name: "tutor", path: "references/curriculum.md"}}

  defp scripted_step(:tutor, _step) do
    {:final,
     """
     Tutor loaded its root instructions and curriculum through progressive disclosure.

     A useful first exercise is to state one result, one scope limit, and one direct check for the VFS calculator task. This is a guided QA response. It does not change the host filesystem.
     """}
  end

  defp tool_response(model, context, step, name, arguments) do
    call = ReqLLM.ToolCall.new("qa-#{step}", name, Jason.encode!(arguments))

    {:ok,
     %ReqLLM.Response{
       id: "qa-response-#{step}",
       model: model,
       context: context,
       message: ReqLLM.Context.assistant("", tool_calls: [call]),
       finish_reason: :tool_calls,
       usage: %{input_tokens: 10, output_tokens: 5}
     }}
  end

  defp final_response(model, context, step, text) do
    {:ok,
     %ReqLLM.Response{
       id: "qa-response-#{step}",
       model: model,
       context: context,
       message: ReqLLM.Context.assistant(text),
       finish_reason: :stop,
       usage: %{input_tokens: 10, output_tokens: 25}
     }}
  end
end
