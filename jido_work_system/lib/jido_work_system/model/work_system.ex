defmodule JidoWorkSystem.Model.WorkSystem do
  use JidoWorkSystem.Model.Base, table: "work_systems"

  attributes do
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:purpose, :string, allow_nil?: false, public?: true)
    attribute(:status, :string, allow_nil?: false, default: "ready", public?: true)
  end

  relationships do
    has_many(:human_actors, JidoWorkSystem.Model.HumanActor)
    has_many(:work_cells, JidoWorkSystem.Model.WorkCell)
    has_many(:tasks, JidoWorkSystem.Model.Task)
  end
end
