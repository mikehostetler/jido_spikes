defmodule JidoWorkSystem.Model.Evidence do
  use JidoWorkSystem.Model.Base, table: "evidence"

  attributes do
    attribute(:kind, :string, allow_nil?: false, public?: true)
    attribute(:content, :string, allow_nil?: false, public?: true)
    attribute(:source, :string, allow_nil?: false, public?: true)
    attribute(:independently_checkable, :boolean, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:task, JidoWorkSystem.Model.Task, allow_nil?: false, attribute_public?: true)
    belongs_to(:mutation, JidoWorkSystem.Model.Mutation, attribute_public?: true)
  end
end
