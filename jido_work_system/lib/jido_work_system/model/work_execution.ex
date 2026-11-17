defmodule JidoWorkSystem.Model.WorkExecution do
  use JidoWorkSystem.Model.Base, table: "work_executions"

  attributes do
    attribute(:status, :string, allow_nil?: false, default: "accepted", public?: true)
    attribute(:current_state, :map, allow_nil?: false, default: %{}, public?: true)
  end

  relationships do
    belongs_to(:task, JidoWorkSystem.Model.Task, allow_nil?: false, attribute_public?: true)

    belongs_to(:work_cell, JidoWorkSystem.Model.WorkCell,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
