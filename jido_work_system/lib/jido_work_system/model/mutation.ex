defmodule JidoWorkSystem.Model.Mutation do
  use JidoWorkSystem.Model.Base, table: "mutations"

  attributes do
    attribute(:prior_state, :map, allow_nil?: false, public?: true)
    attribute(:action, :string, allow_nil?: false, public?: true)
    attribute(:resulting_state, :map, allow_nil?: false, public?: true)
    attribute(:receipt, :string, allow_nil?: false, public?: true)
    attribute(:authorized, :boolean, allow_nil?: false, public?: true)
    attribute(:authority_used, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:task, JidoWorkSystem.Model.Task, allow_nil?: false, attribute_public?: true)

    belongs_to(:work_execution, JidoWorkSystem.Model.WorkExecution,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:authority, JidoWorkSystem.Model.Authority,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
