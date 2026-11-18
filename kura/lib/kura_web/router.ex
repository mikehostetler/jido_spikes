defmodule KuraWeb.Router do
  use KuraWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KuraWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KuraWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/cells", CellsLive
    live "/maintenance", MaintenanceLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", KuraWeb do
  #   pipe_through :api
  # end
end
