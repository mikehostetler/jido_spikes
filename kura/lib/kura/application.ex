defmodule Kura.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        KuraWeb.Telemetry,
        Kura.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:kura, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:kura, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Kura.PubSub},
        Kura.Jido,
        {Registry, keys: :unique, name: Kura.Cell.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: Kura.Cell.Supervisor},
        {Task.Supervisor, name: Kura.Maintenance.ReviewSupervisor},
        Kura.Maintenance
      ] ++
        recovery_children() ++
        [
          # Start to serve requests, typically the last entry
          KuraWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kura.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KuraWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp recovery_children do
    if Application.get_env(:kura, :recover_cells_on_boot, true),
      do: [{Task, &Kura.Cells.recover/0}],
      else: []
  end
end
