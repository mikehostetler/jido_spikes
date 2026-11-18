defmodule Kura.Cell.Workspace do
  @moduledoc false
  alias Jido.Workspace

  @brief "/brief.txt"
  @max_brief_bytes 65_536

  def open(cell) do
    path = directory(cell.id)
    root = Path.dirname(path)

    with :ok <- File.mkdir_p(root),
         :ok <- prepare(path, cell) do
      Workspace.open(
        id: Ash.UUID.generate(),
        policy: :read_only,
        adapter: Jido.VFS.Adapter.Local,
        adapter_opts: [prefix: path]
      )
    end
  end

  def inspect_brief(workspace, cell_id) do
    directory = directory(cell_id)

    with {:ok, %{type: :directory}} <- File.lstat(directory),
         {:ok, %{type: :regular, size: size}} when size <= @max_brief_bytes <-
           File.lstat(Path.join(directory, @brief)),
         {:ok, bytes} when byte_size(bytes) <= @max_brief_bytes <-
           Workspace.read(workspace, @brief),
         true <- String.valid?(bytes) do
      {:ok,
       %{
         "path" => @brief,
         "has_content" => String.trim(bytes) != "",
         "bytes" => byte_size(bytes),
         "sha256" => :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
       }}
    else
      _ -> {:error, :brief_unavailable}
    end
  end

  defp directory(cell_id) do
    root = Application.fetch_env!(:kura, :cell_workspace_root)
    Path.join(root, Base.url_encode64(cell_id, padding: false))
  end

  defp prepare(path, cell) do
    case File.mkdir(path) do
      :ok ->
        brief = get_in(cell, [:workspace, "brief"]) || "Workspace brief for #{cell.id}.\n"
        File.write(Path.join(path, "brief.txt"), brief)

      {:error, :eexist} ->
        :ok

      error ->
        error
    end
  end
end
