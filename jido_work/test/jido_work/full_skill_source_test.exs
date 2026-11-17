defmodule JidoWork.FullSkillSourceTest do
  use ExUnit.Case, async: false

  alias JidoWork.{FullSkillSource, HarnessSource, Runner, Workspace}

  setup do
    :ok = Workspace.reset()
    %{roots: [Runner.skills_root()]}
  end

  test "discovers both complete skill packages", %{roots: roots} do
    assert {:ok, skills} = FullSkillSource.catalog(roots)
    assert Enum.map(skills, & &1.name) == ["jido", "tutor"]
    assert Enum.all?(skills, &(&1.resource_count > 0))
  end

  test "loads root instructions and a nested resource", %{roots: roots} do
    config = %{roots: roots}

    assert {:ok, tools} = FullSkillSource.list_tools(config, %{})
    assert Enum.map(tools, & &1.name) == ["load_skill", "load_skill_resource"]

    assert {:ok, loaded} =
             FullSkillSource.run_tool(
               %{name: "load_skill", arguments: %{name: "jido"}},
               config,
               %{}
             )

    assert loaded.instructions =~ "# Jido"

    source = File.read!(Path.join([Runner.skills_root(), "jido", "SKILL.md"]))
    ["", _frontmatter, full_instructions] = String.split(source, "---", parts: 3)
    assert String.trim(loaded.instructions) == String.trim(full_instructions)

    assert loaded.resource_count > 100
    assert Enum.any?(loaded.resources, &(&1.path == "references/commands.md"))

    assert {_projected, %{truncated: false, max_bytes: 65_536}} =
             Jido.AI.ToolResult.project(loaded, 65_536)

    assert {:ok, resource} =
             FullSkillSource.run_tool(
               %{
                 name: "load_skill_resource",
                 arguments: %{name: "jido", path: "references/commands.md"}
               },
               config,
               %{}
             )

    assert resource.content =~ "Internal Kata registry and routing"
  end

  test "rejects resource traversal", %{roots: roots} do
    assert {:error, %{type: :skill_resource_error, reason: :path_traversal_rejected}} =
             FullSkillSource.run_tool(
               %{
                 name: "load_skill_resource",
                 arguments: %{name: "jido", path: "../tutor/SKILL.md"}
               },
               %{roots: roots},
               %{}
             )
  end

  test "blocks project tools until the required skill route loads", %{roots: roots} do
    :ok = Workspace.require_skill("jido", ["references/commands.md"])
    list_call = %{name: "list_files", arguments: %{pattern: ""}}

    assert {:error, %{type: :skill_required}} =
             HarnessSource.run_tool(list_call, %{}, %{})

    assert {:ok, _loaded} =
             FullSkillSource.run_tool(
               %{name: "load_skill", arguments: %{name: "jido"}},
               %{roots: roots},
               %{}
             )

    assert {:error, %{type: :skill_resource_required}} =
             HarnessSource.run_tool(list_call, %{}, %{})

    assert {:ok, _resource} =
             FullSkillSource.run_tool(
               %{
                 name: "load_skill_resource",
                 arguments: %{name: "jido", path: "references/commands.md"}
               },
               %{roots: roots},
               %{}
             )

    assert {:ok, %{count: 4}} = HarnessSource.run_tool(list_call, %{}, %{})
  end
end
