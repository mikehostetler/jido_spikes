defmodule JidoWork.RunnerTest do
  use ExUnit.Case, async: false

  alias JidoWork.{Runner, Workspace}

  setup do
    :ok = Workspace.reset()
    :ok
  end

  test "ReAct loads Jido resources and uses Jido VFS and Jido Shell" do
    prompt = "$jido Repair and verify the VFS calculator."

    assert {:ok, result} = Runner.run(prompt, :offline, "")
    assert result.status == :completed
    assert result.output =~ "jido` skill and its routing registry loaded"
    assert result.workspace.files["lib/calculator.ex"] =~ "left + right"
    assert result.workspace.skill_gate.status == :satisfied

    tools = Enum.map(result.workspace.events, & &1.tool)
    assert tools == ["load_skill", "load_skill_resource", "read_file", "edit_file", "run_shell"]
    assert result.workspace.runtime.filesystem == "Jido.VFS.Adapter.InMemory"
    assert result.workspace.runtime.shell == "Jido.Shell.Agent"
  end

  test "ReAct loads Tutor and its curriculum resource" do
    prompt = "$tutor Teach one approved topic."

    assert {:ok, result} = Runner.run(prompt, :offline, "")
    assert result.status == :completed
    assert result.output =~ "Tutor loaded"
    assert result.workspace.skill_gate.status == :satisfied

    assert Enum.map(result.workspace.events, & &1.tool) == [
             "load_skill",
             "load_skill_resource"
           ]
  end
end
