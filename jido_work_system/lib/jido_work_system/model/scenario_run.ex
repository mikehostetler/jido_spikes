defmodule JidoWorkSystem.Model.ScenarioRun do
  use JidoWorkSystem.Model.Base, table: "scenario_runs"

  attributes do
    attribute(:scenario_key, :string, allow_nil?: false, public?: true)
    attribute(:status, :string, allow_nil?: false, default: "ready", public?: true)
    attribute(:cursor, :integer, allow_nil?: false, default: 0, public?: true)
    attribute(:revision, :integer, allow_nil?: false, default: 0, public?: true)
    attribute(:current_beat, :string, allow_nil?: false, default: "ready", public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )
  end
end
