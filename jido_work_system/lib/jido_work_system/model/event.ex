defmodule JidoWorkSystem.Model.Event do
  use JidoWorkSystem.Model.Base, table: "events"

  attributes do
    attribute(:sequence, :integer, allow_nil?: false, public?: true)
    attribute(:kind, :string, allow_nil?: false, public?: true)
    attribute(:summary, :string, allow_nil?: false, public?: true)
    attribute(:data, :map, allow_nil?: false, default: %{}, public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:task, JidoWorkSystem.Model.Task, attribute_public?: true)
  end

  identities do
    identity(:unique_sequence, [:work_system_id, :sequence])
  end
end
