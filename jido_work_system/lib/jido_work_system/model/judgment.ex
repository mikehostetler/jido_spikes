defmodule JidoWorkSystem.Model.Judgment do
  use JidoWorkSystem.Model.Base, table: "judgments"

  attributes do
    attribute(:actor_label, :string, allow_nil?: false, public?: true)
    attribute(:situation, :string, allow_nil?: false, public?: true)
    attribute(:observations, {:array, :string}, allow_nil?: false, public?: true)
    attribute(:options, {:array, :string}, allow_nil?: false, public?: true)
    attribute(:decision_text, :string, allow_nil?: false, public?: true)
    attribute(:stated_basis, :string, allow_nil?: false, public?: true)
    attribute(:uncertainty, :string, allow_nil?: false, public?: true)
    attribute(:risk, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:actor, JidoWorkSystem.Model.HumanActor, attribute_public?: true)
    belongs_to(:work_cell, JidoWorkSystem.Model.WorkCell, attribute_public?: true)
    belongs_to(:task, JidoWorkSystem.Model.Task, allow_nil?: false, attribute_public?: true)

    belongs_to(:method, JidoWorkSystem.Model.JudgmentMethod,
      allow_nil?: false,
      attribute_public?: true
    )

    has_one(:decision, JidoWorkSystem.Model.Decision)
  end
end
