defmodule JidoWorkSystem.Model.Accountability do
  use JidoWorkSystem.Model.Base, table: "accountabilities"

  attributes do
    attribute(:subject, :string, allow_nil?: false, public?: true)
    attribute(:acceptance_right, :boolean, allow_nil?: false, default: true, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:human_actor, JidoWorkSystem.Model.HumanActor,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:role, JidoWorkSystem.Model.Role, allow_nil?: false, attribute_public?: true)
  end
end
