defmodule JarvisWeb.MarkdownTest do
  use ExUnit.Case, async: true

  test "renders Markdown and highlights Elixir code with Lumis" do
    html =
      JarvisWeb.Markdown.render("""
      **Ready**

      ```elixir
      IO.puts("hello")
      ```
      """)

    assert html =~ "<strong>Ready</strong>"
    assert html =~ "<pre"
    assert html =~ "style="
  end

  test "does not render raw HTML" do
    html = JarvisWeb.Markdown.render("<script>alert('no')</script>\n\nsafe")

    refute html =~ "<script>"
    assert html =~ "safe"
  end

  test "streams partial Markdown as keyed documents" do
    updates = JarvisWeb.Markdown.stream(["A **bo", "ld** answer."]) |> Enum.to_list()

    html =
      updates
      |> Enum.into(%{}, fn {id, document} ->
        {id, JarvisWeb.Markdown.render_document(document)}
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("\n", &elem(&1, 1))

    assert html =~ "<strong>bold</strong>"
    assert html =~ "answer"
  end
end
