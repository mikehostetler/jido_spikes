defmodule JidoWorkSystem.Model.Outcome do
  use JidoWorkSystem.Model.Base, table: "outcomes"

  attributes do
    attribute(:status, :string, allow_nil?: false, public?: true)
    attribute(:summary, :string, allow_nil?: false, public?: true)
    attribute(:human_acceptance, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:task, JidoWorkSystem.Model.Task, allow_nil?: false, attribute_public?: true)

    belongs_to(:evaluation, JidoWorkSystem.Model.Evaluation,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:accepted_by, JidoWorkSystem.Model.HumanActor, attribute_public?: true)
  end
end
