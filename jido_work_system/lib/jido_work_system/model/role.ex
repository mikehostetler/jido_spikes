defmodule JidoWorkSystem.Model.Role do
  use JidoWorkSystem.Model.Base, table: "roles"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:purpose, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
