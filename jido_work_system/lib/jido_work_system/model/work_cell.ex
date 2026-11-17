defmodule JidoWorkSystem.Model.WorkCell do
  use JidoWorkSystem.Model.Base, table: "work_cells"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:purpose, :string, allow_nil?: false, public?: true)
    attribute(:vsm_cell_id, :string, allow_nil?: false, public?: true)
    attribute(:status, :string, allow_nil?: false, default: "available", public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:parent, __MODULE__, attribute_public?: true)

    belongs_to(:accountable_actor, JidoWorkSystem.Model.HumanActor,
      allow_nil?: false,
      attribute_public?: true
    )

    has_many(:children, __MODULE__, destination_attribute: :parent_id)
    has_many(:work_executions, JidoWorkSystem.Model.WorkExecution)
  end
end
