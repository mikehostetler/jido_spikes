defmodule JidoWorkSystem.Model.JudgmentMethod do
  use JidoWorkSystem.Model.Base, table: "judgment_methods"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:method_type, :string, allow_nil?: false, public?: true)
    attribute(:provider, :string, allow_nil?: false, public?: true)
    attribute(:deterministic, :boolean, allow_nil?: false, default: true, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
