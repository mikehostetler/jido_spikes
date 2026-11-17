defmodule JidoWork.WorkspaceTest do
  use ExUnit.Case, async: false

  alias JidoWork.Workspace

  setup do
    :ok = Workspace.reset()
    :ok
  end

  test "Jido Shell reads files from the same Jido VFS filesystem" do
    assert {:ok, %{output: "/\n", shell: "jido_shell"}} = Workspace.run_shell("pwd")

    assert {:ok, %{output: output}} =
             Workspace.run_shell("ls /lib && cat /lib/calculator.ex")

    assert output =~ "calculator.ex"
    assert output =~ "left - right"
  end

  test "a checked VFS edit is visible through Jido Shell" do
    assert {:ok, %{filesystem: "jido_vfs", changed: true}} =
             Workspace.edit_file("lib/calculator.ex", "left - right", "left + right")

    assert {:ok, %{output: output}} = Workspace.run_shell("cat /lib/calculator.ex")
    assert output =~ "left + right"
  end

  test "the shell tool rejects host commands" do
    assert {:error, %{type: :shell_command_not_allowed, requested: ["mix"]}} =
             Workspace.run_shell("mix test")
  end
end
