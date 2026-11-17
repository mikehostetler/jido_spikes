defmodule JidoWorkSystem.Work do
  use Ash.Domain,
    otp_app: :jido_work_system

  resources do
    resource(JidoWorkSystem.Model.ScenarioRun)
    resource(JidoWorkSystem.Model.WorkSystem)
    resource(JidoWorkSystem.Model.HumanActor)
    resource(JidoWorkSystem.Model.Role)
    resource(JidoWorkSystem.Model.Authority)
    resource(JidoWorkSystem.Model.Accountability)
    resource(JidoWorkSystem.Model.WorkCell)
    resource(JidoWorkSystem.Model.Task)
    resource(JidoWorkSystem.Model.WorkExecution)
    resource(JidoWorkSystem.Model.Delegation)
    resource(JidoWorkSystem.Model.JudgmentMethod)
    resource(JidoWorkSystem.Model.Judgment)
    resource(JidoWorkSystem.Model.Decision)
    resource(JidoWorkSystem.Model.Mutation)
    resource(JidoWorkSystem.Model.Evidence)
    resource(JidoWorkSystem.Model.Evaluation)
    resource(JidoWorkSystem.Model.Outcome)
    resource(JidoWorkSystem.Model.Tool)
    resource(JidoWorkSystem.Model.Workspace)
    resource(JidoWorkSystem.Model.Knowledge)
    resource(JidoWorkSystem.Model.Event)
  end
end
