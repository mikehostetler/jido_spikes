defmodule JidoWorkSystem.Model.Evaluation do
  use JidoWorkSystem.Model.Base, table: "evaluations"

  attributes do
    attribute(:verification_status, :string, allow_nil?: false, public?: true)
    attribute(:verdict, :string, allow_nil?: false, public?: true)
    attribute(:confidence, :decimal, allow_nil?: false, public?: true)
    attribute(:notes, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:task, JidoWorkSystem.Model.Task, allow_nil?: false, attribute_public?: true)

    belongs_to(:evidence, JidoWorkSystem.Model.Evidence,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:evaluator, JidoWorkSystem.Model.HumanActor, attribute_public?: true)
  end
end
