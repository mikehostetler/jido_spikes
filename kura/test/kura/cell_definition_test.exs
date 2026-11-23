defmodule Kura.CellDefinitionTest do
  use Kura.DataCase, async: false

  alias Kura.{Cells, Playbooks}
  alias Kura.Cell.{Control, Definition, Inbox, References}

  @parent "pine-data"
  @child "pine-data/check"

  @tag :tmp_dir
  test "an imported definition starts a cell tree, runs a playbook, and recovers work", %{
    tmp_dir: root
  } do
    previous_root = Application.fetch_env!(:kura, :cell_workspace_root)
    Application.put_env(:kura, :cell_workspace_root, root)

    on_exit(fn ->
      for id <- [@child, @parent], {pid, _} <- Registry.lookup(Kura.Cell.Registry, id) do
        DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, pid)
      end

      Application.put_env(:kura, :cell_workspace_root, previous_root)
    end)

    assert {:ok, @parent} = Cells.import_definition(example())
    assert {:ok, %{module: nil, parent: nil, role_text: role} = parent} = Cells.fetch(@parent)
    assert role =~ "Inspect the local workspace"
    assert {:ok, %{module: nil, parent: @parent, role_text: child_role}} = Cells.fetch(@child)
    assert child_role =~ "Inspect the child workspace"

    assert {:ok, json} = Cells.export_definition(@parent)

    assert get_in(JSON.decode!(json), ["definition", "schema", "id"]) ==
             "kura/vsm/schema/standard"

    assert {:ok, decoded} =
             Jido.Codec.decode_json(json,
               codec: Jido.Agent.Codec,
               catalog: References.definition_catalog()
             )

    assert decoded == parent.definition

    assert {:ok, %{"children" => %{"check" => @child}, "runtime" => runtime}} =
             Jido.Holon.profile(decoded)

    assert runtime["handlers"]["inspect"] == "workspace.inspect@1"

    for {cell, brief} <- [
          {@parent, "The Pine definition supplied this brief.\n"},
          {@child, "This brief belongs to the child only.\n"}
        ] do
      Phoenix.PubSub.subscribe(Kura.PubSub, "cell:" <> cell)
      assert {:ok, entry} = Cells.command(cell, :inspect)
      assert await_command(cell, entry.id).output =~ digest(brief)
    end

    assert {:ok, parent_address} = Control.address(@parent)
    assert {:ok, child_address} = Control.address(@child)

    assert {:ok, %{owner_address: ^parent_address}} =
             Jido.agent_ownership(Kura.Jido, child_address)

    assert {:ok, parent_bus} = Cells.bus(@parent)
    assert {:ok, child_bus} = Cells.bus(@child)
    refute parent_bus == child_bus

    assert {:ok, draft_entry} = Cells.command(@parent, :observe)
    await_command(@parent, draft_entry.id)
    assert {:ok, draft} = Playbooks.get(@parent, draft_entry.id)
    assert {:ok, replayed} = Playbooks.replay(@parent, draft.id)
    assert replayed.replay["passed"]
    assert {:ok, %{active: true}} = Playbooks.approve(@parent, draft.id)

    assert {:ok, pid} = Cells.activate(@parent)
    assert :ok = DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, pid)

    assert {:ok, queued} =
             Inbox.enqueue(@parent, "workspace_observation", %{}, channel: "command")

    assert [{:ok, replacement}] = Cells.recover()
    refute pid == replacement

    assert await_command(@parent, queued.id).output =~ "Playbook v1 recorded SHA-256"
    assert Inbox.next(@parent) == nil
  end

  test "rejects an unknown binding and leaves no part of the cell tree" do
    invalid =
      example()
      |> JSON.decode!()
      |> put_in(["children", "check", "handlers", "inspect"], "Elixir.UntrustedModule")
      |> JSON.encode!()

    assert {:error, _} = Cells.import_definition(invalid)
    assert {:error, :unknown_cell} = Cells.fetch(@parent)
    assert {:error, :unknown_cell} = Cells.fetch(@child)

    assert {:ok, @parent} = Cells.import_definition(example())
    assert {:error, {:cell_already_exists, @parent}} = Cells.import_definition(example())
  end

  test "loads saved definitions that use either earlier plugin ID" do
    assert {:ok, @parent} = Cells.import_definition(example())
    stored = Definition.fetch(@parent)
    document = JSON.encode!(stored.document)
    assert document =~ "jido.holon"

    for id <- ["kura/cell", "jido.work_cell/cell"] do
      legacy =
        document
        |> String.replace("jido.holon", id)
        |> JSON.decode!()

      Kura.Repo.update!(Ecto.Changeset.change(stored, document: legacy))

      assert {:ok, legacy_cell} = Cells.fetch(@parent)
      assert {:ok, %{"role" => %{"text" => _}}} = Jido.Holon.profile(legacy_cell.definition)
      assert {:ok, exported} = Cells.export_definition(@parent)
      assert exported =~ "jido.holon"
    end
  end

  defp example do
    :kura |> Application.app_dir("priv/cells/examples/pine-data.json") |> File.read!()
  end

  defp digest(brief), do: :crypto.hash(:sha256, brief) |> Base.encode16(case: :lower)

  defp await_command(cell, id) do
    case Cells.latest_command(cell) do
      %{id: ^id, status: "completed"} = entry ->
        entry

      %{id: ^id, status: "blocked", output: reason} ->
        flunk(reason)

      _ ->
        assert_receive :cell_changed, 5_000
        await_command(cell, id)
    end
  end
end
