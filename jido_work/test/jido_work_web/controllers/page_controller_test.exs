defmodule JidoWorkWeb.PageControllerTest do
  use JidoWorkWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the Jido VFS and Shell workspace", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#jido-work")
    assert has_element?(view, "[data-testid='skills-panel']")
    assert has_element?(view, "[data-testid='workspace-panel']")
    assert has_element?(view, "[data-testid='skill-gate-status']")
  end
end
