defmodule Section9.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Section9.PubSub},
      {Registry, keys: :unique, name: Section9.ActorRegistry},
      {Jido,
       name: Section9.Jido,
       namespace: "spikes/section9",
       persistence: {Jido.Persistence.ETS, table: Section9.JidoStore}},
      Section9.ViableWorkCell.Runtime,
      Section9.Ledger,
      {DynamicSupervisor, strategy: :one_for_one, name: Section9.ActorSupervisor},
      Section9.Team,
      Section9Web.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Section9.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Section9Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
