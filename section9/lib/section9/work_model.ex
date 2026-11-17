defmodule Section9.WorkTask do
  @moduledoc """
  The prescribed part of one assignment.

  The task states the required output and its limits. It does not contain the
  judgment that an actor must use to complete the task.
  """

  @enforce_keys [
    :id,
    :purpose,
    :output,
    :quantity,
    :quality,
    :by_when,
    :accountable_role,
    :authority,
    :resources,
    :discretion_scope,
    :escalation_conditions
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          purpose: String.t(),
          output: String.t(),
          quantity: String.t(),
          quality: String.t(),
          by_when: String.t(),
          accountable_role: atom(),
          authority: :read_only | :local_write | :external_write,
          resources: map(),
          discretion_scope: String.t(),
          escalation_conditions: [String.t()]
        }

  @doc "Returns the complete repair assignment used by the simulation."
  @spec repair(keyword()) :: t()
  def repair(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, "human-repair-1"),
      purpose: "Restore correct JobServer cancellation behavior",
      output: "One repaired JobServer candidate",
      quantity: "One source artifact and one evaluation result",
      quality:
        "All protected normal, cancellation, late-result, duplicate-result, and regression checks pass",
      by_when: Keyword.get(opts, :by_when, "before the end of this simulation"),
      accountable_role: :human_owner,
      authority: :local_write,
      resources: %{pulse_limit: 12, cost_usd: Keyword.get(opts, :cost_usd, 0)},
      discretion_scope:
        "The cell can diagnose and edit the fixture. It cannot edit protected checks or external systems.",
      escalation_conditions: [
        "The required authority is not available",
        "The mission budget is exhausted",
        "An emergency signal is active",
        "Independent evaluation does not pass"
      ]
    }
  end

  @doc "Converts the assignment to the current Viable Work Cell contract."
  @spec to_contract(t()) :: map()
  def to_contract(%__MODULE__{} = task) do
    %{
      id: task.id,
      purpose: task.purpose,
      done_when: task.quality,
      authority: task.authority,
      budget: task.resources,
      task: Map.from_struct(task)
    }
  end
end

defmodule Section9.HumanActor do
  @moduledoc """
  A deterministic human actor model.

  A judgment record shows the situation, available choices, decision, and
  stated basis. The basis is inspection data. It is not hidden reasoning.
  """

  @enforce_keys [:id, :role, :authority]
  defstruct [:id, :role, :authority, judgments: []]

  @type authority :: :read_only | :local_write | :external_write
  @type judgment :: %{
          sequence: pos_integer(),
          situation: atom(),
          observations: map(),
          options: [atom()],
          decision: atom(),
          basis: String.t()
        }
  @type t :: %__MODULE__{
          id: String.t(),
          role: atom(),
          authority: authority(),
          judgments: [judgment()]
        }

  @doc "Creates the human who remains accountable for the assigned result."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :human_id, "human-owner"),
      role: Keyword.get(opts, :role, :human_owner),
      authority: Keyword.get(opts, :authority, :local_write)
    }
  end

  @doc "Records one explicit use of judgment."
  @spec judge(t(), atom(), map(), [atom()], atom(), String.t()) :: {:ok, t()} | {:error, term()}
  def judge(%__MODULE__{} = actor, situation, observations, options, decision, basis)
      when is_atom(situation) and is_map(observations) and is_list(options) and is_atom(decision) and
             is_binary(basis) do
    if decision in options do
      judgment = %{
        sequence: length(actor.judgments) + 1,
        situation: situation,
        observations: observations,
        options: options,
        decision: decision,
        basis: basis
      }

      {:ok, %{actor | judgments: actor.judgments ++ [judgment]}}
    else
      {:error, {:decision_not_available, decision}}
    end
  end

  @doc "Checks that the human can authorize the task before delegation."
  @spec can_assign?(t(), Section9.WorkTask.t()) :: boolean()
  def can_assign?(%__MODULE__{authority: actor_authority}, %Section9.WorkTask{
        authority: task_authority
      }) do
    authority_rank(actor_authority) >= authority_rank(task_authority)
  end

  defp authority_rank(:read_only), do: 0
  defp authority_rank(:local_write), do: 1
  defp authority_rank(:external_write), do: 2
end

defmodule Section9.HumanWorkSimulation do
  @moduledoc """
  A human-to-cell engagement loop.

  The human prescribes and delegates a task. The Viable Work Cell controls and
  executes it. The human then accepts the evidence or responds to escalation.
  """

  alias Section9.{HumanActor, ViableWorkCell, WorkTask}

  @doc "Runs one deterministic human engagement with the Viable Work Cell."
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    actor = HumanActor.new(opts)
    task = WorkTask.repair(opts)
    pressure = Keyword.get(opts, :pressure, :normal)

    with true <- HumanActor.can_assign?(actor, task),
         {:ok, actor} <- assignment_judgment(actor, task, pressure) do
      outcome = ViableWorkCell.run(WorkTask.to_contract(task), opts)
      review(actor, task, pressure, outcome)
    else
      false -> {:error, {:insufficient_human_authority, actor.authority, task.authority}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp assignment_judgment(actor, task, pressure) do
    HumanActor.judge(
      actor,
      :assign_work,
      %{
        task_id: task.id,
        required_output: task.output,
        by_when: task.by_when,
        pressure: pressure
      },
      [:delegate, :hold, :escalate],
      :delegate,
      "The task is inside my authority, has a bounded output, and has explicit completion checks."
    )
  end

  defp review(actor, task, pressure, {:ok, report}) do
    decision = if report.verify.passed, do: :accept, else: :request_rework

    with {:ok, actor} <-
           HumanActor.judge(
             actor,
             :review_result,
             %{
               task_id: task.id,
               verified: report.verify.passed,
               evaluation_id: report.verify.evaluation_id
             },
             [:accept, :request_rework, :escalate],
             decision,
             review_basis(decision)
           ) do
      {:ok, simulation_report(actor, task, pressure, decision, {:ok, report})}
    end
  end

  defp review(actor, task, pressure, {:error, {:work_escalated, evidence}} = outcome) do
    with {:ok, actor} <-
           HumanActor.judge(
             actor,
             :respond_to_escalation,
             %{task_id: task.id, evidence: evidence},
             [:stop_and_review, :reframe, :seek_authority],
             :stop_and_review,
             "The cell reported an emergency. The human does not override the stop condition."
           ) do
      {:ok, simulation_report(actor, task, pressure, :stopped, outcome)}
    end
  end

  defp review(actor, task, pressure, {:error, reason} = outcome) do
    with {:ok, actor} <-
           HumanActor.judge(
             actor,
             :respond_to_failure,
             %{task_id: task.id, reason: inspect(reason)},
             [:investigate, :reframe, :abandon],
             :investigate,
             "The result is not verified. The task cannot close."
           ) do
      {:ok, simulation_report(actor, task, pressure, :needs_investigation, outcome)}
    end
  end

  defp review_basis(:accept), do: "Independent checks passed, so the assigned output is accepted."

  defp review_basis(:request_rework),
    do: "Independent checks did not pass, so the task needs rework."

  defp simulation_report(actor, task, pressure, status, outcome) do
    %{
      status: status,
      distinction: %{
        task: "The prescribed output and its limits.",
        work: "The judgment used to complete the task under uncertainty.",
        control: "The cell regulation that authorizes, stops, or escalates action.",
        evidence: "The record used to evaluate the output."
      },
      accountable_actor: actor.id,
      human: %{id: actor.id, role: actor.role, judgments: actor.judgments},
      task: Map.from_struct(task),
      cell: %{id: "viable-work-cell", pressure: pressure, outcome: outcome}
    }
  end
end
