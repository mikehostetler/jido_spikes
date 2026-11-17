defmodule Section9Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :section9

  @session_options [
    store: :cookie,
    key: "_section9_key",
    signing_salt: "section9-session",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static, at: "/", from: :section9, gzip: false, only: ~w(assets))
  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(Section9Web.Router)
end
