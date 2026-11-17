defmodule JidoWorkSystem.RunSnapshot do
  @moduledoc false

  alias JidoWorkSystem.Model
  alias JidoWorkSystem.Store

  @collection_keys ~w(
    humans roles authorities accountabilities cells tasks work delegations methods judgments
    decisions mutations evidence evaluations outcomes tools workspaces knowledge events
  )a

  def empty do
    Map.merge(%{run: nil, system: nil}, Map.new(@collection_keys, &{&1, []}))
  end

  def build(run) do
    system = Store.get!(Model.WorkSystem, run.work_system_id)
    system_id = system.id

    tasks = Store.where(Model.Task, :work_system_id, system_id)
    task_ids = Enum.map(tasks, & &1.id)
    judgments = Store.where_in(Model.Judgment, :task_id, task_ids)

    %{
      run: run,
      system: system,
      humans: Store.where(Model.HumanActor, :work_system_id, system_id),
      roles: Store.where(Model.Role, :work_system_id, system_id),
      authorities: Store.where(Model.Authority, :work_system_id, system_id),
      accountabilities: Store.where(Model.Accountability, :work_system_id, system_id),
      cells: Store.where(Model.WorkCell, :work_system_id, system_id),
      tasks: tasks,
      work: Store.where_in(Model.WorkExecution, :task_id, task_ids),
      delegations: Store.where_in(Model.Delegation, :task_id, task_ids),
      methods: Store.where(Model.JudgmentMethod, :work_system_id, system_id),
      judgments: judgments,
      decisions: Store.where_in(Model.Decision, :judgment_id, Enum.map(judgments, & &1.id)),
      mutations: Store.where_in(Model.Mutation, :task_id, task_ids),
      evidence: Store.where_in(Model.Evidence, :task_id, task_ids),
      evaluations: Store.where_in(Model.Evaluation, :task_id, task_ids),
      outcomes: Store.where_in(Model.Outcome, :task_id, task_ids),
      tools: Store.where(Model.Tool, :work_system_id, system_id),
      workspaces: Store.where(Model.Workspace, :work_system_id, system_id),
      knowledge: Store.where(Model.Knowledge, :work_system_id, system_id),
      events:
        Model.Event
        |> Store.where(:work_system_id, system_id)
        |> Enum.sort_by(& &1.sequence)
    }
  end
end
