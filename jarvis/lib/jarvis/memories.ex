defmodule Jarvis.Memories do
  @moduledoc "Typed, namespaced local memory with deterministic SQLite FTS5 recall."

  @behaviour Jarvis.Memory.Store

  import Ecto.Query, warn: false

  alias Jarvis.Memories.Memory
  alias Jarvis.Repo

  @classes ~w(semantic episodic procedural working)
  @default_limit 5
  @stopwords ~w(a an and are as at be by do for from how i in is it me my of on or the to what when where which who why with you your)

  def classes, do: @classes

  @doc "Lists active memories with the most recent item first."
  def list_memories(opts \\ []) do
    namespace = Keyword.get(opts, :namespace)

    Memory
    |> where([memory], is_nil(memory.forgotten_at) and is_nil(memory.superseded_by_id))
    |> maybe_namespace(namespace)
    |> order_by([memory], desc: memory.updated_at, desc: memory.id)
    |> Repo.all()
  end

  @doc "Gets one memory, including a forgotten or superseded record."
  def get_memory!(id), do: Repo.get!(Memory, id)

  @doc "Stores one typed memory."
  @impl Jarvis.Memory.Store
  def remember(attrs) do
    %Memory{}
    |> Memory.changeset(normalize_attrs(attrs))
    |> Repo.insert()
  end

  @doc "Returns active FTS5 matches in relevance order, with recency as a tie-breaker."
  @impl Jarvis.Memory.Store
  def recall(namespace, text, opts \\ []) when is_binary(namespace) and is_binary(text) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> clamp_limit()
    classes = Keyword.get(opts, :classes, @classes)

    with {:ok, fts_query} <- fts_query(text),
         true <- valid_classes?(classes) do
      placeholders = Enum.map_join(classes, ", ", fn _ -> "?" end)

      sql = """
      SELECT m.id
      FROM memories_fts
      JOIN memories AS m ON m.id = memories_fts.rowid
      WHERE memories_fts MATCH ?
        AND m.namespace = ?
        AND m.class IN (#{placeholders})
        AND m.forgotten_at IS NULL
        AND m.superseded_by_id IS NULL
      ORDER BY bm25(memories_fts) ASC, m.updated_at DESC, m.id DESC
      LIMIT ?
      """

      params = [fts_query, namespace] ++ classes ++ [limit]
      %{rows: rows} = Ecto.Adapters.SQL.query!(Repo, sql, params)
      ids = Enum.map(rows, &hd/1)
      by_id = Memory |> where([m], m.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})
      Enum.map(ids, &Map.fetch!(by_id, &1))
    else
      _ -> []
    end
  end

  @doc "Marks one memory forgotten without deleting its original record."
  def forget(%Memory{} = memory) do
    memory
    |> Memory.changeset(%{forgotten_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  @doc "Creates a replacement and links the original record to it."
  def supersede(%Memory{} = memory, attrs) do
    Repo.transaction(fn ->
      replacement_attrs =
        memory
        |> Map.take([:title, :content, :namespace, :class, :metadata])
        |> Map.merge(canonical_attrs(attrs))
        |> normalize_attrs()

      replacement = remember(replacement_attrs) |> unwrap!()

      memory
      |> Memory.changeset(%{superseded_by_id: replacement.id})
      |> Repo.update()
      |> unwrap!()

      replacement
    end)
  end

  @doc "Returns a memory changeset."
  def change_memory(%Memory{} = memory, attrs \\ %{}), do: Memory.changeset(memory, attrs)

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> canonical_attrs()
    |> put_default(:namespace, "user")
    |> put_default(:class, "semantic")
    |> put_default(:metadata, %{})
  end

  defp canonical_attrs(attrs) do
    attrs
    |> Enum.reduce(%{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)

      {key, value}, acc when key in ~w(title content namespace class metadata) ->
        Map.put(acc, String.to_existing_atom(key), value)

      _entry, acc ->
        acc
    end)
  end

  defp put_default(attrs, key, value) do
    string_key = Atom.to_string(key)

    if Map.has_key?(attrs, key) or Map.has_key?(attrs, string_key) do
      attrs
    else
      Map.put(attrs, key, value)
    end
  end

  defp fts_query(text) do
    tokens =
      text
      |> String.downcase()
      |> then(&Regex.scan(~r/[\p{L}\p{N}_]+/u, &1))
      |> List.flatten()
      |> Enum.reject(&(String.length(&1) < 2 or &1 in @stopwords))
      |> Enum.uniq()

    if tokens == [], do: :error, else: {:ok, Enum.map_join(tokens, " OR ", &~s("#{&1}"))}
  end

  defp clamp_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@default_limit)
  defp clamp_limit(_limit), do: @default_limit

  defp valid_classes?(classes),
    do: is_list(classes) and classes != [] and Enum.all?(classes, &(&1 in @classes))

  defp maybe_namespace(query, nil), do: query

  defp maybe_namespace(query, namespace),
    do: where(query, [memory], memory.namespace == ^namespace)

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, changeset}), do: Repo.rollback(changeset)
end
