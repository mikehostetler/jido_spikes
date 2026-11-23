defmodule Kura.CellsTest do
  use Kura.DataCase, async: false

  alias Jido.Signal.Bus
  alias Kura.Cell.{Control, Host, Inbox}
  alias Kura.Cells

  @tag :tmp_dir
  test "isolates work, chat, and memory and recovers queued work", %{tmp_dir: directory} do
    original_root = Application.fetch_env!(:kura, :cell_workspace_root)
    Application.put_env(:kura, :cell_workspace_root, directory)

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Kura.Cell.Supervisor) do
        DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, pid)
      end

      Application.put_env(:kura, :cell_workspace_root, original_root)
    end)

    assert {:ok, cedar_bus} = Cells.bus("cedar")
    assert {:ok, review_bus} = Cells.bus("cedar/review")
    assert {:ok, pine_bus} = Cells.bus("pine")
    assert length(Enum.uniq([cedar_bus, review_bus, pine_bus])) == 3

    assert {:ok, %{output: reply}} = Cells.chat("pine", "What is your status?")
    assert reply =~ "No work has run."

    assert {:ok, %{input: "Check the report again tomorrow."}} =
             Cells.remember("pine", "Check the report again tomorrow.")

    assert Cells.history("pine", "command") == []
    assert Cells.history("cedar/review", "chat") == []
    assert Cells.history("cedar/review", "memory") == []

    assert {:ok, %{id: review_id}} =
             Cells.signal(
               "cedar/review",
               Jido.Signal.new!("kura.workspace.inspect", %{}, source: "/tests")
             )

    assert {:ok, %{id: pine_id}} = Cells.command("pine", :inspect)
    assert [review] = await_work("cedar/review", review_id)
    assert [pine] = await_work("pine", pine_id)
    assert review.output =~ "Control: kura:delivery:#{review.id}:"
    assert pine.output =~ "Control: kura:delivery:#{pine.id}:"

    for {cell, result} <- [{"cedar/review", review}, {"pine", pine}] do
      digest =
        :crypto.hash(:sha256, "Workspace brief for #{cell}.\n")
        |> Base.encode16(case: :lower)

      assert result.output =~ digest
    end

    assert {:ok, []} = Bus.replay(cedar_bus, "kura.cell.command")

    events =
      wait(
        fn ->
          assert {:ok, events} = Bus.replay(review_bus, "kura.cell.command")

          if Enum.any?(events, &(&1.signal.data == %{entry_id: review_id, status: "completed"})),
            do: events
        end,
        System.monotonic_time(:millisecond) + 5_000
      )

    refute Enum.any?(events, &(&1.signal.data.entry_id == pine_id))

    assert {:ok, parent} = Control.address("cedar")
    assert {:ok, child} = Control.address("cedar/review")
    assert {:ok, %{owner_address: ^parent}} = Jido.agent_ownership(Kura.Jido, child)

    assert {:ok, pid} = Cells.activate("pine")
    assert :ok = DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, pid)

    assert {:ok, %{id: queued_id}} =
             Inbox.enqueue("pine", "inspect", %{}, channel: "command", input: "Inspect workspace")

    assert [{:ok, replacement}] = Cells.recover()
    assert replacement != pid

    assert [%{id: ^pine_id}, %{id: ^queued_id, trace: %{"status" => "local_demo"}}] =
             await_work("pine", queued_id)

    assert Inbox.next("pine") == nil
    assert [%{input: "Check the report again tomorrow."}] = Cells.history("pine", "memory")
    assert [%{input: "What is your status?"}] = Cells.history("pine", "chat")
  end

  defmodule PausedPulse do
    def run(_cell, _workspace, entry) do
      send(Process.whereis(__MODULE__), {:pulse_started, self(), entry.id})

      receive do
        :finish -> {{:ok, "Recovered once"}, nil}
      end
    end
  end

  test "stopping a cell during a pulse stops its active handler before recovery" do
    Process.register(self(), PausedPulse)
    {:ok, cell} = Cells.fetch("pine")
    cell = %{cell | pulse_handlers: %{"paused" => PausedPulse}}

    on_exit(fn ->
      for {pid, _} <- Registry.lookup(Kura.Cell.Registry, cell.id) do
        DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, pid)
      end
    end)

    assert {:ok, queued} = Inbox.enqueue(cell.id, "paused", %{}, channel: "command")
    id = queued.id
    assert {:ok, worker} = Jido.Holon.activate(cell, Host.options())
    assert_receive {:pulse_started, attempt, ^id}, 2_000
    monitor = Process.monitor(attempt)
    assert :ok = DynamicSupervisor.terminate_child(Kura.Cell.Supervisor, worker)
    assert_receive {:DOWN, ^monitor, :process, ^attempt, _}
    assert %{id: ^id} = Inbox.next(cell.id)

    assert {:ok, replacement} = Jido.Holon.activate(cell, Host.options())
    assert_receive {:pulse_started, ^replacement, ^id}, 2_000
    send(replacement, :finish)

    assert [%{id: ^id, output: "Recovered once"}] = await_work(cell.id, id)
    refute_receive {:pulse_started, _, ^id}
  end

  test "round trips both Jido plugins in a canonical Agent definition" do
    assert :ok = Jido.Catalog.Discovery.refresh()
    assert {:ok, json} = Cells.export_definition("cedar")
    assert %{"type" => "jido.agent.definition", "vsn" => 1} = JSON.decode!(json)
    assert {:ok, decoded} = Jido.Codec.decode_json(json, codec: Jido.Agent.Codec)
    assert decoded == Kura.Cells.Cedar.definition()

    assert {:ok,
            %{
              "role" => "cedar/ROLE.md",
              "skills" => ["jido"],
              "children" => %{"review" => Kura.Cells.Inspector},
              "playbooks" => %{"inspect" => ["read_brief", "check_brief"]}
            }} = Jido.Holon.profile(decoded)
  end

  defp await_work(cell, id) do
    wait(
      fn ->
        entries = Cells.history(cell, "command")
        entry = Enum.find(entries, &(&1.id == id))
        assert entry.status != "blocked", inspect(entry.output)
        if entry.status == "completed", do: entries
      end,
      System.monotonic_time(:millisecond) + 5_000
    )
  end

  defp wait(fun, deadline) do
    case fun.() do
      nil ->
        assert System.monotonic_time(:millisecond) < deadline, "work did not complete"
        Process.sleep(20)
        wait(fun, deadline)

      value ->
        value
    end
  end
end
