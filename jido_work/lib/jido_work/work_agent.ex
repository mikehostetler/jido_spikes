defmodule JidoWork.WorkAgent do
  @moduledoc "A Jido v3 ReAct agent for complete Agent Skills packages."

  use Jido.AI.Agent, name: "jido_work_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model("lmstudio:runtime-selected")

      instructions("""
      You are a coding agent in a confined Jido VFS and Jido Shell harness.

      When a request starts with $jido or $tutor, call load_skill with that exact skill name before
      you do other work. The returned value contains the root instructions and a resource manifest.
      When loaded instructions name a relative file, call load_skill_resource with the loaded skill
      name and that exact relative path. Follow progressive disclosure: load only the files required
      for the current route. Use read_file only for the VFS project, never for skill resources.

      The project files use Jido VFS and shell commands use Jido Shell. Both are confined to an
      in-memory VFS. State this limit. Do not claim that an edit changes the host filesystem. Do not
      commit, publish, install software, or request credentials.

      The target paths are lib/calculator.ex and test/calculator_test.exs. Read those paths directly
      after the selected skill route is loaded. Do not call list_files. After a checked edit, call
      run_shell with `cat /lib/calculator.ex` to verify the VFS content. Jido Shell does not expose
      host `mix` or `git` commands.
      """)

      limits do
        elapsed_ms(300_000)
        model_calls(12)
        tool_rounds(8)
        tool_calls(16)
        tool_output_bytes(65_536)
      end
    end
  end
end
