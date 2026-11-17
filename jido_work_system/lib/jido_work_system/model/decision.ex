defmodule JidoWorkSystem.Model.Decision do
  use JidoWorkSystem.Model.Base, table: "decisions"

  attributes do
    attribute(:choice, :string, allow_nil?: false, public?: true)
    attribute(:status, :string, allow_nil?: false, default: "effective", public?: true)
  end

  relationships do
    belongs_to(:judgment, JidoWorkSystem.Model.Judgment,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
