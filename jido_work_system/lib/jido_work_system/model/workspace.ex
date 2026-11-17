defmodule JidoWorkSystem.Model.Workspace do
  use JidoWorkSystem.Model.Base, table: "workspaces"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:root, :string, allow_nil?: false, public?: true)
    attribute(:boundary, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
