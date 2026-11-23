defmodule ConnectBotWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :connect_bot

  plug(Plug.RequestId)
  plug(Plug.Parsers, parsers: [:urlencoded])

  plug(Plug.Session,
    store: :cookie,
    key: "_connect_bot",
    signing_salt: "connect-bot-session",
    encryption_salt: "connect-bot-encryption",
    same_site: "Lax"
  )

  plug(ConnectBotWeb.Router)
end
