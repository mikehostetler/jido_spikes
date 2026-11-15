defmodule JarvisWeb.ChatLiveTest do
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the Jarvis chat page", %{conn: conn} do
    conversation = "test-#{System.unique_integer([:positive])}"
    {:ok, _view, html} = live(conn, "/?conversation=#{conversation}")

    assert html =~ "Jarvis"
    assert html =~ "qwen3-coder-next:q8_0"
    assert html =~ "Message Jarvis"
    refute html =~ "Control"
    refute html =~ "Run as verified objective"
  end
end
