defmodule JidoWorkSystem.Model.Delegation do
  use JidoWorkSystem.Model.Base, table: "delegations"

  attributes do
    attribute(:status, :string, allow_nil?: false, default: "offered", public?: true)
    attribute(:terms, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:task, JidoWorkSystem.Model.Task, allow_nil?: false, attribute_public?: true)

    belongs_to(:from_actor, JidoWorkSystem.Model.HumanActor,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:to_cell, JidoWorkSystem.Model.WorkCell,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:authority, JidoWorkSystem.Model.Authority,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
