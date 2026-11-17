defmodule JidoWorkSystem.Model.Authority do
  use JidoWorkSystem.Model.Base, table: "authorities"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:scope, :string, allow_nil?: false, public?: true)

    attribute(:permitted_actions, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true
    )

    attribute(:limits, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:holder, JidoWorkSystem.Model.HumanActor, attribute_public?: true)
    belongs_to(:role, JidoWorkSystem.Model.Role, attribute_public?: true)
  end
end
