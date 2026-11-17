defmodule JidoWorkSystemWeb.Router do
  use JidoWorkSystemWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JidoWorkSystemWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", JidoWorkSystemWeb do
    pipe_through :browser

    live "/", SimulationLive, :index
    live "/runs/:id", SimulationLive, :show
    live "/runs/:id/debug", SimulationDebugLive, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", JidoWorkSystemWeb do
  #   pipe_through :api
  # end
end
