defmodule KuraWeb.CellsTest do
  use KuraWeb.ConnCase

  test "opens the nested cell with separate operator inputs", %{conn: conn} do
    alias Kura.Cell.Journal

    {:ok, entry} = Journal.record("cedar/review", "command", "Inspect workspace", "queued")

    Journal.finish(entry, {:ok, "The brief has content."}, %{
      "model" => "openai:gpt-6.1-terra",
      "tools" => [
        %{
          "name" => "read_workspace_brief",
          "arguments" => %{},
          "status" => "ok",
          "result" => %{"path" => "/brief.txt", "sha256" => "sample-digest"}
        }
      ]
    })

    body = conn |> get(~p"/cells?#{[id: "cedar/review"]}") |> html_response(200)

    assert body =~ "Workspace inspector"
    assert body =~ "Latest run"
    assert body =~ "Inspect workspace"
    assert body =~ "Cell chat"
    assert body =~ "Cell memory"
    assert body =~ "read_workspace_brief({})"
    assert body =~ "sample-digest"
  end

  test "shows an imported cell and its child", %{conn: conn} do
    json = :kura |> Application.app_dir("priv/cells/examples/pine-data.json") |> File.read!()
    assert {:ok, "pine-data"} = Kura.Cells.import_definition(json)

    body = conn |> get(~p"/cells?#{[id: "pine-data"]}") |> html_response(200)

    assert body =~ "Pine from data"
    assert body =~ "pine-data%2Fcheck"

    child = conn |> get(~p"/cells?#{[id: "pine-data/check"]}") |> html_response(200)
    assert child =~ "Pine check"
    assert child =~ "Inspect the child workspace"
    assert body =~ "Inspect the local workspace"
    assert body =~ "Local demo mode"
    assert body =~ "Create a draft"
  end
end
