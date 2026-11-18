defmodule Kura.Playbooks.Storage do
  @moduledoc "SQLite checkpoints for Loom. Rebinds the HTN from its pinned JSON version."

  @behaviour Jido.Loom.Storage

  import Ecto.Query
  alias Jido.Loom.{Error, Kernel, ProjectedState, Run}
  alias Jido.Loom.Core.RunReducer
  alias Kura.{Playbooks, Repo}
  alias Kura.Playbooks.Version

  defmodule Record do
    use Ecto.Schema

    @primary_key {:id, :string, autogenerate: false}
    schema "loom_records" do
      field :version_id, :string
      field :revision, :integer
      field :checkpoint, :binary
    end
  end

  @impl true
  def persist_run_transition(previous, events, run, snapshot) do
    with :ok <- validate_transition(previous, events, run) do
      key = "run:" <> run.id
      version_id = run.playbook_ref.playbook_id
      checkpoint = pack({%{run | definition: nil}, snapshot})
      attrs = %{checkpoint: checkpoint, revision: run.rev}

      count =
        if previous.rev == 0 do
          {count, _} =
            Repo.insert_all(Record, [Map.merge(attrs, %{id: key, version_id: version_id})],
              on_conflict: :nothing
            )

          count
        else
          {count, _} =
            from(row in Record,
              where:
                row.id == ^key and row.revision == ^previous.rev and row.version_id == ^version_id
            )
            |> Repo.update_all(set: Map.to_list(attrs))

          count
        end

      if count == 1, do: {:ok, run}, else: {:error, Error.policy("Loom run revision changed")}
    end
  end

  defp validate_transition(previous, events, next) do
    if previous.id == next.id and next.event_log == previous.event_log ++ events and
         next.rev == previous.rev + length(events) do
      :ok
    else
      {:error, Error.validation("Invalid Loom transition")}
    end
  end

  @impl true
  def get_run(id) do
    with {:ok, row} <- fetch("run:" <> id),
         {:ok, {%Run{} = run, _}} <- unpack(row.checkpoint),
         %Version{} = version <- Repo.get(Version, row.version_id),
         {:ok, definition} <- Playbooks.definition(version, run_mode(run)) do
      {:ok, %{run | definition: definition}}
    else
      nil -> {:error, Error.not_found("Pinned playbook version missing")}
      error -> error
    end
  end

  defp run_mode(%{initial_input: %{"fixture_replay" => true}}), do: :fixture
  defp run_mode(_run), do: :work

  @impl true
  def replay_run(id) do
    with {:ok, run} <- get_run(id) do
      base = %{
        run
        | status: :created,
          projected_state: ProjectedState.new!(%{data: run.initial_input}),
          next_task_instance_id: nil,
          method_selections: [],
          task_instances: [],
          event_log: [],
          wait_points: [],
          rev: 0,
          updated_at: run.inserted_at
      }

      {:ok, RunReducer.apply_events(base, run.event_log)}
    end
  end

  @impl true
  def list_run_events(id) do
    with {:ok, row} <- fetch("run:" <> id),
         {:ok, {%Run{} = run, _}} <- unpack(row.checkpoint),
         do: {:ok, run.event_log}
  end

  @impl true
  def get_snapshot(:run, id) do
    with {:ok, row} <- fetch("run:" <> id),
         {:ok, {%Run{}, snapshot}} <- unpack(row.checkpoint),
         do: {:ok, snapshot}
  end

  def get_snapshot(:session, id), do: read("snapshot:" <> id)

  @impl true
  def put_snapshot(%{scope: :session, id: id} = snapshot), do: put("snapshot:" <> id, snapshot)
  def put_snapshot(%{scope: :run, run_id: id}), do: get_snapshot(:run, id)

  @impl true
  def put_session(session) do
    with {:ok, _} <-
           put(
             "session:" <> session.id,
             {%{session | active_run: nil}, session.active_run && session.active_run.id}
           ),
         do: {:ok, session}
  end

  @impl true
  def get_session(id) do
    case read("session:" <> id) do
      {:ok, {session, nil}} ->
        {:ok, session}

      {:ok, {session, run_id}} ->
        with {:ok, run} <- get_run(run_id), do: {:ok, %{session | active_run: run}}

      error ->
        error
    end
  end

  @impl true
  def put_run(%Run{rev: 0}), do: {:error, Error.validation("A Loom run needs initial events")}

  def put_run(%Run{} = run) do
    with {:ok, current} <- get_run(run.id),
         true <- current.rev == run.rev and current.event_log == run.event_log do
      {:ok, current}
    else
      false -> {:error, Error.policy("Use persist_run_transition to change a run")}
      error -> error
    end
  end

  @impl true
  def append_run_events(id, events) do
    with {:ok, run} <- get_run(id),
         next = RunReducer.apply_events(run, events),
         {:ok, _} <- persist_run_transition(run, events, next, Kernel.snapshot(next)),
         do: {:ok, events}
  end

  @impl true
  def delete_run(id), do: delete("run:" <> id)

  @impl true
  def delete_session(id) do
    delete("snapshot:" <> id)
    delete("session:" <> id)
  end

  defp delete(key) do
    Repo.delete_all(from row in Record, where: row.id == ^key)
    :ok
  end

  defp fetch(key) do
    case Repo.get(Record, key) do
      nil -> {:error, Error.not_found("Loom record missing", %{id: key})}
      row -> {:ok, row}
    end
  end

  defp put(key, value) do
    record = %Record{id: key, checkpoint: pack(value), revision: 0}

    with {:ok, _} <-
           Repo.insert(record, on_conflict: {:replace, [:checkpoint]}, conflict_target: [:id]),
         do: {:ok, value}
  end

  defp read(key) do
    with {:ok, row} <- fetch(key), do: unpack(row.checkpoint)
  end

  defp pack(value), do: :erlang.term_to_binary({1, value})

  defp unpack(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      {1, value} -> {:ok, value}
      _ -> {:error, Error.validation("Unsupported Loom checkpoint version")}
    end
  rescue
    ArgumentError -> {:error, Error.validation("Invalid Loom checkpoint")}
  end
end
