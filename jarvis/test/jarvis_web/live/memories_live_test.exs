defmodule JarvisWeb.MemoriesLiveTest do
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "creates, edits, and deletes a memory", %{conn: conn} do
    {:ok, view, html} = live(conn, "/memories")
    assert html =~ "No memories yet"

    view
    |> form("#memory-form", memory: %{title: "Preferred editor", content: "Use **Neovim**."})
    |> render_submit()

    assert has_element?(view, "#memories article", "Preferred editor")
    assert render(view) =~ "<strong>Neovim</strong>"

    memory = Jarvis.Memories.list_memories() |> List.first()
    original_id = memory.id

    view
    |> element("#memory-#{memory.id} button", "Edit")
    |> render_click()

    view
    |> form("#memory-form", memory: %{title: "Preferred tools", content: "Use `rg`."})
    |> render_submit()

    replacement = Jarvis.Memories.list_memories() |> List.first()
    assert replacement.id != original_id
    assert Jarvis.Memories.get_memory!(original_id).superseded_by_id == replacement.id
    assert has_element?(view, "#memory-#{replacement.id}", "Preferred tools")

    view
    |> element("#memory-#{replacement.id} button", "Delete")
    |> render_click()

    refute has_element?(view, "#memory-#{replacement.id}")
    assert Jarvis.Memories.get_memory!(replacement.id).forgotten_at
    assert has_element?(view, "#empty-memories")
  end

  test "validates required fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/memories")

    view
    |> form("#memory-form", memory: %{title: "", content: ""})
    |> render_change()

    assert has_element?(view, ".field-error", "can't be blank")
  end
end
