defmodule JidoWorkSystem.Model.Knowledge do
  use JidoWorkSystem.Model.Base, table: "knowledge"

  attributes do
    attribute(:title, :string, allow_nil?: false, public?: true)
    attribute(:content, :string, allow_nil?: false, public?: true)
    attribute(:provenance, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
