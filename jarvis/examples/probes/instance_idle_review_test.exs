defmodule Jarvis.InstanceIdleReviewTest do
  use ExUnit.Case, async: false

  @instance Jarvis.IdleProbe
  @id "idle-probe"
  @settled [:jido, :agent_server, :turn, :settled]
  @persist [:jido, :persistence, :operation, :stop]
  @effects [:jido, :agent_server, :effects, :stop]

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Jarvis.Repo, shared: true)
    old = Application.fetch_env(:jido, :ai_inference_client)
    Application.put_env(:jido, :ai_inference_client, Jarvis.TestInferenceClient)
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(handler, [@settled, @persist, @effects], &__MODULE__.event/4, self())

    on_exit(fn ->
      :telemetry.detach(handler)

      case old do
        {:ok, client} -> Application.put_env(:jido, :ai_inference_client, client)
        :error -> Application.delete_env(:jido, :ai_inference_client)
      end

      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    start_supervised!(
      {Jido,
       name: @instance,
       namespace: "jarvis-idle-test",
       persistence: {Jido.Persistence.ETS, table: Jarvis.IdleProbeStore},
       activation: [idle_residency_timeout: 1_500]}
    )

    {:ok, address} = Jido.agent_address(@instance, @id)
    {:ok, ^address} = Jido.create_agent(@instance, address, Jarvis.Agent)
    %{address: address}
  end

  def event(event, _, %{agent_id: id} = m, dest) when is_binary(id) do
    if String.starts_with?(id, @id) and
         (event == @settled or m[:persistence_reason] == :hibernate or m[:status] == :error) do
      send(dest, {:trace, event, id, m[:signal_type], m[:status], m[:trace_id]})
    end
  end

  def event(_, _, _, _), do: :ok

  test "a scheduled review returns to the root after the instance goes idle", %{address: address} do
    purpose = "checkout idle trace"

    {:ok, memory} =
      Jarvis.Memories.remember(%{
        namespace: "jarvis",
        title: purpose,
        content: "Rollback complete."
      })

    start =
      Jido.Signal.new!("jarvis.schedule.start", %{purpose: purpose, interval_ms: 300},
        source: "/test"
      )

    {:ok, first} = Jido.activate_agent(@instance, address)
    :ok = Jido.AgentServer.await_ready(first)
    monitor = Process.monitor(first)
    assert_receive {:DOWN, ^monitor, :process, ^first, _}, 6_000
    assert_receive {:trace, @persist, @id, nil, :ok, _}, 1_000
    {:ok, root} = Jido.activate_agent(@instance, address)
    :ok = Jido.AgentServer.await_ready(root)
    assert {:ok, %{status: :committed}} = Jido.AgentServer.call(root, start)
    cell = @id <> "/$topology/vsm/1/initial"
    s4 = cell <> "/$topology/s4/1/initial"
    s5 = cell <> "/$topology/s5/1/initial"

    # Start emits an immediate review. Check the later timer ticks separately.
    for tick <- 0..10 do
      assert_receive {:trace, @settled, @id, "jarvis.vsm.review", :ok, trace}, 2_000
      assert_receive {:trace, @settled, ^cell, "jarvis.vsm.review.requested", :ok, ^trace}, 1_000

      receive do
        {:trace, @effects, ^cell, "jarvis.vsm.review.requested", :error, ^trace} ->
          state = Jido.AgentServer.snapshot(root).agent.state

          flunk(
            "Review #{tick} (0 = immediate) stopped at Cell -> S4; trace #{trace}. " <>
              "Root recorded #{state.reviews} reviews; timer: #{Jarvis.ReviewSchedule.status(state).status}."
          )

        {:trace, @settled, ^s4, "jarvis.vsm.review.requested", :ok, ^trace} ->
          :ok
      after
        1_000 -> flunk("No S4 delivery for review #{tick}, trace #{trace}")
      end

      assert_receive {:trace, @settled, ^s5, "jarvis.vsm.recommendation", :ok, ^trace}, 1_000
      assert_receive {:trace, @settled, ^cell, "jarvis.vsm.review.completed", :ok, ^trace}, 1_000
      assert_receive {:trace, @settled, @id, "jarvis.vsm.review.completed", :ok, ^trace}, 1_000
      state = Jido.AgentServer.snapshot(root).agent.state
      assert state.reviews >= tick + 1
      assert state.last_review.memory_ids == [memory.id]
    end
  end
end
