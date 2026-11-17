defmodule JidoWorkWeb.PageController do
  use JidoWorkWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
