defmodule Section9.ViableWorkCell.Cell do
  @moduledoc "The smallest recursive VSM cell for Section 9 work."

  use Jido.VSM.Cell, name: "section9_viable_work_cell"

  vsm do
    operation(:delivery)
    operation(:learning)
  end
end

defmodule Section9.ViableWorkCell.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer

  @instance Section9.Jido
  @cell_id "viable-work-cell"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec cell() :: pid()
  def cell, do: GenServer.call(__MODULE__, :cell)

  @impl true
  def init(:ok) do
    with {:ok, cell} <- Jido.start_agent(@instance, Section9.ViableWorkCell.Cell, id: @cell_id),
         :ok <- AgentServer.await_ready(cell) do
      {:ok, %{cell: cell}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:cell, _from, state), do: {:reply, state.cell, state}
end

defmodule Section9.ViableWorkCell.Work do
  @moduledoc "Effect and result-check contract for one viable work cell."

  @callback perform(contract :: map(), opts :: keyword()) :: {:ok, term()} | {:error, term()}
  @callback verify(result :: term(), contract :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end

defmodule Section9.ViableWorkCell.RepairWork do
  @moduledoc "Section 9 repair work behind the viable-cell effect boundary."

  @behaviour Section9.ViableWorkCell.Work

  alias Section9.{Demo, Ledger, Model, Team}

  @impl true
  def perform(_contract, opts) do
    if Keyword.get(opts, :reset, true), do: Demo.reset()
    Team.run_auto(model_adapter: Keyword.get(opts, :model_adapter, Model.Fake))
  end

  @impl true
  def verify(_result, _contract, _opts) do
    snapshot = Ledger.snapshot()

    if (snapshot.mission.status == "closed" and snapshot.task.status == "closed" and
          snapshot.evaluation) && snapshot.evaluation.passed do
      {:ok,
       %{
         mission: snapshot.mission.status,
         task: snapshot.task.status,
         evaluation_id: snapshot.evaluation.id,
         passed: true,
         checks:
           snapshot.evaluation.evidence["checks"] ||
             snapshot.evaluation.evidence[:checks] || []
       }}
    else
      {:error,
       {:work_not_verified,
        %{
          mission: snapshot.mission.status,
          task: snapshot.task.status,
          evaluation: snapshot.evaluation
        }}}
    end
  end
end

defmodule Section9.ViableWorkCell do
  @moduledoc """
  A small, executable viable work loop.

  The local `jido_vsm` package supplies the native Jido Cell, its S1 operation
  Agents, and its S2, S3, S3*, S4, and S5 Agents. Section 9 adds a typed work
  contract, an effect boundary, domain verification, and a compact report.
  """

  alias Jido.AgentServer
  alias Jido.VSM.Signal.{Emergency, ExternalRequest, Pain}
  alias Section9.ViableWorkCell.Runtime

  @instance Section9.Jido
  @cell_id "viable-work-cell"
  @default_timeout 3_000
  @roles ~w(s2 s3 s3_star s4 s5)
  @operations ~w(delivery learning)

  @type contract :: %{
          required(:id) => String.t(),
          required(:purpose) => String.t(),
          required(:done_when) => String.t(),
          required(:authority) => :read_only | :local_write | :external_write,
          required(:budget) => map(),
          optional(:task) => map()
        }

  @doc "Runs one VSM-regulated work loop and returns evidence for each stage."
  @spec run(contract(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(contract, opts \\ [])

  def run(contract, opts) when is_map(contract) do
    work_module = Keyword.get(opts, :work_module, Section9.ViableWorkCell.RepairWork)
    pressure = Keyword.get(opts, :pressure, :normal)

    with {:ok, contract} <- validate_contract(contract),
         {:ok, before} <- snapshot(),
         :ok <- apply_pressure(contract.id, pressure, before, opts),
         :ok <- authorize_pressure(pressure),
         {:ok, %{status: :committed}} <- request(contract),
         {:ok, controlled} <- await_cycle(contract.id, before, opts),
         {:ok, authorization} <- authorize(contract, controlled),
         {:ok, effect_result} <- work_module.perform(contract, opts),
         {:ok, verification} <- work_module.verify(effect_result, contract, opts) do
      {:ok,
       report(
         contract,
         pressure,
         authorization,
         effect_result,
         verification,
         controlled
       )}
    end
  end

  def run(_contract, _opts), do: {:error, :contract_must_be_a_map}

  @doc "Sends an explicit pain or emergency signal through S3, S4, and S5."
  @spec steer(:pain | :emergency, String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def steer(level, reason, opts \\ []) when level in [:pain, :emergency] and is_binary(reason) do
    request_id = "steer-#{System.unique_integer([:positive, :monotonic])}"

    with {:ok, before} <- snapshot(),
         :ok <- send_pressure(level, request_id, reason),
         {:ok, after_snapshot} <- await_pressure(level, request_id, before, opts) do
      {:ok,
       %{
         request_id: request_id,
         level: level,
         s3: Map.take(after_snapshot.roles["s3"], [:pain_count, :emergency_count]),
         s5:
           Map.take(after_snapshot.roles["s5"], [
             :pain_count,
             :emergency_count,
             :last_recommendation
           ])
       }}
    end
  end

  @doc "Returns the current root, operation, and management role state."
  @spec snapshot() :: {:ok, map()} | {:error, term()}
  def snapshot do
    agents = residents()

    root =
      find_state(agents, fn state ->
        state[:operations] == @operations and is_nil(state[:role])
      end)

    operations =
      Map.new(@operations, fn operation ->
        {operation, find_state(agents, &(&1[:operation] == operation))}
      end)

    roles =
      Map.new(@roles, fn role ->
        {role, find_state(agents, &(&1[:role] == role))}
      end)

    if not is_nil(root) and Enum.all?(operations, fn {_name, state} -> not is_nil(state) end) and
         Enum.all?(roles, fn {_name, state} -> not is_nil(state) end) do
      {:ok, %{root: root, operations: operations, roles: roles}}
    else
      {:error, :viable_work_cell_not_ready}
    end
  end

  defp request(contract) do
    signal =
      ExternalRequest.new!(%{
        request_id: contract.id,
        target: "all",
        payload: %{
          purpose: contract.purpose,
          done_when: contract.done_when,
          authority: Atom.to_string(contract.authority),
          budget: contract.budget
        }
      })

    AgentServer.call(Runtime.cell(), signal)
  end

  defp validate_contract(contract) do
    required = [:id, :purpose, :done_when, :authority, :budget]
    optional = [:task]
    missing = Enum.reject(required, &valid_field?(contract, &1))

    cond do
      missing != [] ->
        {:error, {:missing_contract_fields, missing}}

      contract.authority not in [:read_only, :local_write, :external_write] ->
        {:error, {:invalid_authority, contract.authority}}

      true ->
        {:ok, Map.take(contract, required ++ optional)}
    end
  end

  defp valid_field?(contract, field) do
    case Map.fetch(contract, field) do
      {:ok, value} when value not in [nil, "", %{}] -> true
      _ -> false
    end
  end

  defp apply_pressure(_request_id, :normal, _before, _opts), do: :ok

  defp apply_pressure(request_id, level, before, opts) when level in [:pain, :emergency] do
    with :ok <- send_pressure(level, request_id, "work cell pressure is #{level}"),
         {:ok, _snapshot} <- await_pressure(level, request_id, before, opts) do
      :ok
    end
  end

  defp apply_pressure(_request_id, pressure, _before, _opts),
    do: {:error, {:invalid_pressure, pressure}}

  defp send_pressure(level, request_id, reason) do
    module = if level == :pain, do: Pain, else: Emergency
    signal = module.new!(%{request_id: request_id, reason: reason})

    case AgentServer.call(Runtime.cell(), signal) do
      {:ok, %{status: :committed}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_pressure(:emergency),
    do: {:error, {:work_escalated, %{reason: :emergency_stop}}}

  defp authorize_pressure(_pressure), do: :ok

  defp authorize(%{authority: :read_only}, _snapshot),
    do: {:error, {:work_not_authorized, :read_only}}

  defp authorize(_contract, snapshot) do
    {:ok,
     %{
       decision: :authorized,
       commands_issued: snapshot.roles["s3"].commands_issued,
       verified_controls: snapshot.roles["s3_star"].commands_seen,
       policy_recommendations: snapshot.roles["s5"].recommendations_seen
     }}
  end

  defp await_cycle(request_id, before, opts) do
    timeout = Keyword.get(opts, :control_timeout, @default_timeout)

    await(
      fn snapshot ->
        completed? =
          Enum.all?(@operations, fn operation ->
            state = snapshot.operations[operation]

            state.request_count > before.operations[operation].request_count and
              state.command_count > before.operations[operation].command_count and
              state.last_request_id == request_id
          end)

        management_complete? =
          snapshot.roles["s3"].commands_issued >= before.roles["s3"].commands_issued + 2 and
            snapshot.roles["s3_star"].verifications_made >=
              before.roles["s3_star"].verifications_made + 4 and
            snapshot.roles["s5"].recommendations_seen >=
              before.roles["s5"].recommendations_seen + 4

        completed? and management_complete?
      end,
      timeout,
      :control_timeout
    )
  end

  defp await_pressure(level, request_id, before, opts) do
    timeout = Keyword.get(opts, :control_timeout, @default_timeout)
    counter = if level == :pain, do: :pain_count, else: :emergency_count

    await(
      fn snapshot ->
        snapshot.roles["s3"][counter] > before.roles["s3"][counter] and
          snapshot.roles["s5"][counter] > before.roles["s5"][counter] and
          snapshot.roles["s5"].last_request_id == request_id
      end,
      timeout,
      :pressure_timeout
    )
  end

  defp await(predicate, timeout, timeout_reason) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await(predicate, deadline, timeout_reason)
  end

  defp do_await(predicate, deadline, timeout_reason) do
    case snapshot() do
      {:ok, snapshot} ->
        if predicate.(snapshot) do
          {:ok, snapshot}
        else
          wait_or_timeout(predicate, deadline, timeout_reason)
        end

      {:error, _reason} ->
        wait_or_timeout(predicate, deadline, timeout_reason)
    end
  end

  defp wait_or_timeout(predicate, deadline, timeout_reason) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, timeout_reason}
    else
      receive do
      after
        10 -> do_await(predicate, deadline, timeout_reason)
      end
    end
  end

  defp report(contract, pressure, authorization, effect, verification, snapshot) do
    %{
      cell: @cell_id,
      request_id: contract.id,
      purpose: %{goal: contract.purpose, done_when: contract.done_when},
      task: Map.get(contract, :task),
      sense: %{
        pressure: pressure,
        operation_requests:
          Map.new(@operations, fn operation ->
            {operation, snapshot.operations[operation].request_count}
          end)
      },
      decide: %{
        coordinated_reports: snapshot.roles["s2"].reports_seen,
        commands_issued: snapshot.roles["s3"].commands_issued
      },
      authorize: authorization,
      act: effect,
      verify: verification,
      remember: %{
        jido_persistence: :ets,
        work_ledger: :sqlite,
        policy_version: snapshot.roles["s5"].policy_version
      },
      escalate: %{
        pain_count: snapshot.roles["s5"].pain_count,
        emergency_count: snapshot.roles["s5"].emergency_count
      },
      recursive_state: %{
        operations: @operations,
        management_roles: @roles,
        resident_agents: length(residents())
      }
    }
  end

  defp residents do
    case Jido.list_agents(@instance) do
      agents when is_list(agents) ->
        Enum.filter(agents, fn {id, _pid} ->
          id == @cell_id or String.starts_with?(id, @cell_id <> "/")
        end)

      _other ->
        []
    end
  end

  defp find_state(agents, predicate) do
    Enum.find_value(agents, fn {_id, pid} ->
      state = AgentServer.snapshot(pid).agent.state
      if predicate.(state), do: state
    end)
  end
end
