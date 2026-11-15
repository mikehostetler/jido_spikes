defmodule Jarvis.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Lumis.Languages.async_load(~w(elixir html css javascript json typescript))

    children = [
      Jarvis.Repo,
      JarvisWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:jarvis, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jarvis.PubSub},
      {Jido,
       name: Jarvis.Jido,
       namespace: "spikes/jarvis",
       persistence: {Jido.Persistence.ETS, table: Jarvis.JidoStore}},
      {Task.Supervisor, name: Jarvis.TaskSupervisor},
      Jarvis.Runtime.child_spec(),
      JarvisWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Jarvis.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    JarvisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
