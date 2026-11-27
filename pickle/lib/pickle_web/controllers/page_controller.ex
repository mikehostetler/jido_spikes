defmodule PickleWeb.PageController do
  use PickleWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
