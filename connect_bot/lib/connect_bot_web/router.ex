defmodule ConnectBotWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", ConnectBotWeb do
    pipe_through(:browser)

    get("/", Dashboard, :show)
    post("/agents/:slot/connect", Dashboard, :connect)
    post("/agents/:slot/import", Dashboard, :import_key)
    post("/agents/:slot/read", Dashboard, :read)
    post("/agents/:slot/disconnect", Dashboard, :disconnect)
    get("/integrations/github/oauth/callback", Dashboard, :callback)
  end
end
