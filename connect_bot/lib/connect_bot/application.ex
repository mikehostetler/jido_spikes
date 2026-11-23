defmodule ConnectBot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    jido = {Jido, name: ConnectBot.Jido}

    children =
      if Application.get_env(:connect_bot, :headless, false) do
        [jido]
      else
        [ConnectBot.Store, jido, ConnectBotWeb.Endpoint]
      end

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: ConnectBot.Supervisor
    )
  end
end
