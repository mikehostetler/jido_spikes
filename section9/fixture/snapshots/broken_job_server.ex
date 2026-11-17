defmodule Section9Fixture.JobServer do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})
  def start(server, ref, owner \\ self()), do: GenServer.call(server, {:start, ref, owner})
  def cancel(server, ref), do: GenServer.call(server, {:cancel, ref})
  def deliver(server, ref, value), do: GenServer.cast(server, {:result, ref, value})
  def sync(server), do: GenServer.call(server, :sync)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:start, ref, owner}, _from, pending) do
    {:reply, :ok, Map.put(pending, ref, owner)}
  end

  def handle_call({:cancel, ref}, _from, pending) do
    if owner = pending[ref], do: send(owner, {:job_cancelled, ref})
    {:reply, :ok, pending}
  end

  def handle_call(:sync, _from, pending), do: {:reply, :ok, pending}

  @impl true
  def handle_cast({:result, ref, value}, pending) do
    if owner = pending[ref], do: send(owner, {:job_result, ref, value})
    {:noreply, pending}
  end
end
