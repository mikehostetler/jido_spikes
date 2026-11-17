defmodule JidoWorkSystem.Model.HumanActor do
  use JidoWorkSystem.Model.Base, table: "human_actors"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:kind, :string, allow_nil?: false, default: "human", public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )

    has_many(:accountabilities, JidoWorkSystem.Model.Accountability)
  end
end
