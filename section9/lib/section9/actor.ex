defmodule Section9.Actor do
  @moduledoc "Supervised persistent actor with stable identity and ledger-backed state."

  use GenServer, restart: :permanent

  def start_link(role) do
    GenServer.start_link(__MODULE__, role, name: via(role))
  end

  def child_spec(role) do
    %{id: {__MODULE__, role}, start: {__MODULE__, :start_link, [role]}, restart: :permanent}
  end

  def pulse(role, opts \\ []), do: GenServer.call(via(role), {:pulse, opts}, 180_000)
  def interrupt_next(role), do: GenServer.call(via(role), :interrupt_next)
  def pid(role), do: GenServer.whereis(via(role))
  def via(role), do: {:via, Registry, {Section9.ActorRegistry, role}}

  @impl true
  def init(role) do
    _ = Section9.Ledger.reconcile_actor(role)
    {:ok, %{role: role, crash_after_candidate: false}}
  end

  @impl true
  def handle_call(:interrupt_next, _from, state) do
    {:reply, :ok, %{state | crash_after_candidate: true}}
  end

  def handle_call({:pulse, opts}, _from, state) do
    opts = Keyword.put(opts, :crash_after_candidate, state.crash_after_candidate)
    result = Section9.Cycle.run(state.role, opts)
    {:reply, result, %{state | crash_after_candidate: false}}
  end
end
