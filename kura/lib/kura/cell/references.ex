defmodule Kura.Cell.References do
  @moduledoc false

  alias Jido.Catalog
  alias Jido.Catalog.Manifest
  alias Jido.VSM.{Action, Agent}
  alias Kura.Cell.{Control, Plugin}

  @definition_providers [
    __MODULE__,
    Plugin,
    Jido.VSM.Cell.Plugin,
    Action.RouteExternalRequest,
    Agent.S1,
    Agent.S2,
    Agent.S3,
    Agent.S3Star,
    Agent.S4,
    Agent.S5
  ]

  def definition_catalog do
    @definition_providers
    |> Enum.map(fn module ->
      Manifest.new!(
        module,
        Application.get_application(module),
        module.__jido_catalog_manifest__()
      )
    end)
    |> Catalog.new!()
  end

  # Jido discovers the Agent, Plugin, and schema refs from their own manifests.
  # Register the additional values used by the native VSM topology.
  def __jido_catalog_manifest__ do
    atoms = [
      :adapter,
      :operations,
      :delivery,
      :operation,
      :readiness,
      :s2,
      :s3,
      :s3_star,
      :s4,
      :s5,
      :name,
      :kind,
      :root,
      :agent
    ]

    {:ok, standard} = Control.standard_definition("standard")

    [
      %{id: "kura/vsm/schema/standard", target: standard.schema},
      %{id: "kura/vsm/adapter", target: Kura.Cell.Control.Adapter}
      | Enum.map(atoms, &%{id: "kura/vsm/atom/#{&1}", target: &1})
    ]
  end
end
