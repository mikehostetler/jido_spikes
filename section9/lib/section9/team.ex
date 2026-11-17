defmodule Section9.Team do
  @moduledoc "Starts the fixed team and drives step or automatic mode through one pulse path."

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  def step(role, opts \\ []), do: Section9.Actor.pulse(role, opts)
  def run_auto(opts \\ []), do: GenServer.call(__MODULE__, {:run_auto, opts}, 600_000)

  @impl true
  def init(:ok) do
    :ok = Section9.SkillPackage.load_all()

    Enum.each(Section9.RolePolicy.roles(), fn role ->
      {:ok, _pid} =
        DynamicSupervisor.start_child(Section9.ActorSupervisor, {Section9.Actor, role})
    end)

    {:ok, %{}}
  end

  @impl true
  def handle_call({:run_auto, opts}, _from, state) do
    {:reply, do_run_auto(opts, []), state}
  end

  defp do_run_auto(opts, receipts) do
    snapshot = Section9.Ledger.snapshot()

    case snapshot.task.status do
      "closed" ->
        {:ok, Enum.reverse(receipts)}

      status when status in ["pending", "rework", "passed"] ->
        pulse_and_continue(:lead, opts, receipts)

      "claimed" ->
        pulse_and_continue(:implementer, opts, receipts)

      "candidate_ready" ->
        pulse_and_continue(:evaluator, opts, receipts)

      other ->
        {:error, {:automatic_mode_blocked, other, Enum.reverse(receipts)}}
    end
  end

  defp pulse_and_continue(role, opts, receipts) do
    case safe_pulse(role, opts) do
      {:ok, receipt} ->
        do_run_auto(opts, [{role, receipt} | receipts])

      {:duplicate, receipt} ->
        do_run_auto(opts, [{role, receipt} | receipts])

      {:actor_restarted, reason} ->
        wait_for_actor(role, System.monotonic_time(:millisecond) + 5_000)
        do_run_auto(opts, [{role, %{recovered_from: inspect(reason)}} | receipts])

      {:error, reason} ->
        {:error, {role, reason, Enum.reverse(receipts)}}
    end
  end

  defp safe_pulse(role, opts) do
    Section9.Actor.pulse(role, opts)
  catch
    :exit, reason -> {:actor_restarted, reason}
  end

  defp wait_for_actor(role, deadline) do
    if Section9.Actor.pid(role) do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        raise "actor #{role} did not restart"
      else
        receive do
        after
          5 -> wait_for_actor(role, deadline)
        end
      end
    end
  end
end
