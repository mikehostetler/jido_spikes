defmodule KuraWeb.PageControllerTest do
  use KuraWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "A Durable Work Cell spike for the Jido Work System."
  end
end
