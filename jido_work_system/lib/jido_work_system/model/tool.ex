defmodule JidoWorkSystem.Model.Tool do
  use JidoWorkSystem.Model.Base, table: "tools"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:capability, :string, allow_nil?: false, public?: true)
    attribute(:allowed_path, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:workspace, JidoWorkSystem.Model.Workspace,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
