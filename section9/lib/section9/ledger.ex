defmodule Section9.Ledger do
  @moduledoc "Durable SQLite source of truth for missions, actors, work, and evidence."

  use GenServer

  alias Exqlite.Sqlite3
  alias Section9.BoundedState

  @mission_id "repair-1"
  @task_id "repair-job-server"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def reset_demo(opts \\ []), do: GenServer.call(__MODULE__, {:reset_demo, opts})
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def context(role), do: GenServer.call(__MODULE__, {:context, role})
  def events, do: GenServer.call(__MODULE__, :events)
  def latest_pulses, do: GenServer.call(__MODULE__, :latest_pulses)

  def commit_pulse(
        role,
        pulse_id,
        input,
        state_before,
        proposal,
        expected_generation,
        evidence \\ nil
      ) do
    GenServer.call(
      __MODULE__,
      {:commit_pulse, role, pulse_id, input, state_before, proposal, expected_generation,
       evidence},
      30_000
    )
  end

  def save_uncertain_candidate(pulse_id, source, generation) do
    GenServer.call(__MODULE__, {:save_uncertain_candidate, pulse_id, source, generation})
  end

  def reconcile_actor(role), do: GenServer.call(__MODULE__, {:reconcile_actor, role})
  def expire_and_reclaim(role), do: GenServer.call(__MODULE__, {:expire_and_reclaim, role})

  def record_skill_load(role, skill),
    do: GenServer.call(__MODULE__, {:record_skill_load, role, skill})

  @impl true
  def init(_opts) do
    path = Application.fetch_env!(:section9, :db_path)

    if path != ":memory:" do
      path |> Path.dirname() |> File.mkdir_p!()
    end

    {:ok, db} = Sqlite3.open(path)
    :ok = Sqlite3.set_busy_timeout(db, 5_000)
    :ok = migrate(db)

    if scalar(db, "SELECT COUNT(*) FROM missions", []) == 0 do
      seed(db, [])
    end

    {:ok, %{db: db}}
  end

  @impl true
  def terminate(_reason, %{db: db}), do: Sqlite3.close(db)

  @impl true
  def handle_call({:reset_demo, opts}, _from, state) do
    {:reply, seed(state.db, opts), state}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, build_snapshot(state.db), state}

  def handle_call({:context, role}, _from, state),
    do: {:reply, build_context(state.db, role), state}

  def handle_call(:events, _from, state), do: {:reply, event_rows(state.db), state}
  def handle_call(:latest_pulses, _from, state), do: {:reply, pulse_rows(state.db), state}

  def handle_call({:record_skill_load, role, skill}, _from, state) do
    result =
      transaction(state.db, fn db ->
        exec!(
          db,
          """
          INSERT INTO actor_skills (role, name, root_digest, resources_json, loaded_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(role, name) DO UPDATE SET
            root_digest = excluded.root_digest,
            resources_json = excluded.resources_json,
            loaded_at = excluded.loaded_at
          """,
          [to_string(role), skill.name, skill.root_digest, encode(skill.resources), now()]
        )

        event!(db, "actor_skill_loaded", %{
          role: role,
          name: skill.name,
          root_digest: skill.root_digest,
          resources: skill.resources
        })

        :ok
      end)

    publish_if_committed(result)
    {:reply, result, state}
  end

  def handle_call(
        {:commit_pulse, role, pulse_id, input, state_before, proposal, expected_generation,
         evidence},
        _from,
        state
      ) do
    result =
      transaction(state.db, fn db ->
        case row(db, "SELECT receipt_json FROM effects WHERE idempotency_key = ?", [pulse_id]) do
          [receipt_json] ->
            {:duplicate, Jason.decode!(receipt_json)}

          nil ->
            assert_budget!(db)
            action = proposal["action"]
            receipt = apply_action!(db, role, action, expected_generation, evidence)
            revision = commit_actor_state!(db, role, proposal["next_state"])

            number =
              scalar(db, "SELECT pulses_used + 1 FROM missions WHERE id = ?", [@mission_id])

            now = now()

            exec!(db, "UPDATE missions SET pulses_used = pulses_used + 1 WHERE id = ?", [
              @mission_id
            ])

            exec!(
              db,
              """
              INSERT INTO pulses
                (id, mission_id, role, number, input_json, state_before_json, state_after_json,
                 output_json, stream_text, status, started_at, finished_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'committed', ?, ?)
              """,
              [
                pulse_id,
                @mission_id,
                to_string(role),
                number,
                encode(input),
                encode(state_before),
                encode(proposal["next_state"]),
                encode(proposal),
                proposal["narrative"],
                now,
                now
              ]
            )

            receipt = Map.merge(receipt, %{"state_revision" => revision, "pulse" => number})

            exec!(
              db,
              "INSERT INTO effects VALUES (?, ?, ?, 'committed', ?, ?, ?)",
              [pulse_id, to_string(role), action["type"], encode(action), encode(receipt), now]
            )

            event!(db, "pulse_committed", %{
              role: role,
              pulse_id: pulse_id,
              action: action["type"],
              state_revision: revision
            })

            {:ok, receipt}
        end
      end)

    publish_if_committed(result)
    {:reply, result, state}
  end

  def handle_call({:save_uncertain_candidate, pulse_id, source, generation}, _from, state) do
    result =
      transaction(state.db, fn db ->
        assert_current_claim!(db, :implementer, generation)
        digest = digest(source)
        candidate_id = "candidate-#{generation}-#{String.slice(digest, 0, 10)}"
        diff = Section9.Fixture.diff(source)
        now = now()

        exec!(
          db,
          """
          INSERT OR IGNORE INTO candidates
            (id, task_id, claim_generation, source, diff, digest, status, created_at)
          VALUES (?, ?, ?, ?, ?, ?, 'saved_unreported', ?)
          """,
          [candidate_id, @task_id, generation, source, diff, digest, now]
        )

        exec!(
          db,
          "INSERT OR IGNORE INTO effects VALUES (?, 'implementer', 'submit_candidate', 'uncertain', ?, NULL, ?)",
          [pulse_id, encode(%{candidate_id: candidate_id, generation: generation}), now]
        )

        event!(db, "candidate_saved_before_report", %{
          candidate_id: candidate_id,
          generation: generation,
          pulse_id: pulse_id
        })

        {:ok, candidate_id}
      end)

    publish_if_committed(result)
    {:reply, result, state}
  end

  def handle_call({:reconcile_actor, :implementer}, _from, state) do
    result =
      transaction(state.db, fn db ->
        task = task_map(db)

        candidate =
          row(
            db,
            """
            SELECT id, claim_generation FROM candidates
            WHERE task_id = ? AND status = 'saved_unreported'
            ORDER BY created_at DESC LIMIT 1
            """,
            [@task_id]
          )

        case candidate do
          [candidate_id, generation]
          when generation == task.claim_generation and task.status == "claimed" ->
            exec!(db, "UPDATE candidates SET status = 'ready' WHERE id = ?", [candidate_id])

            exec!(
              db,
              "UPDATE tasks SET status = 'candidate_ready', candidate_id = ?, updated_at = ? WHERE id = ?",
              [candidate_id, now(), @task_id]
            )

            exec!(
              db,
              "UPDATE effects SET status = 'reconciled', receipt_json = ? WHERE status = 'uncertain'",
              [encode(%{candidate_id: candidate_id, reconciled: true})]
            )

            event!(db, "uncertain_candidate_reconciled", %{
              candidate_id: candidate_id,
              generation: generation
            })

            {:reconciled, candidate_id}

          _ ->
            :nothing_to_reconcile
        end
      end)

    publish_if_committed(result)
    {:reply, result, state}
  end

  def handle_call({:reconcile_actor, _role}, _from, state),
    do: {:reply, :nothing_to_reconcile, state}

  def handle_call({:expire_and_reclaim, role}, _from, state) do
    result =
      transaction(state.db, fn db ->
        task = task_map(db)
        generation = task.claim_generation + 1

        exec!(
          db,
          """
          UPDATE tasks SET status = 'claimed', owner = ?, claim_generation = ?, lease_until = ?,
            candidate_id = NULL, evaluation_id = NULL, updated_at = ? WHERE id = ?
          """,
          [to_string(role), generation, lease_until(), now(), @task_id]
        )

        event!(db, "claim_replaced", %{
          role: role,
          old_generation: task.claim_generation,
          generation: generation
        })

        {:ok, generation}
      end)

    publish_if_committed(result)
    {:reply, result, state}
  end

  defp apply_action!(_db, role, %{"type" => "wait"}, _generation, _evidence) do
    %{"action" => "wait", "role" => to_string(role)}
  end

  defp apply_action!(db, :lead, %{"type" => "assign_implementer"}, _generation, _evidence) do
    task = task_map(db)

    unless task.status in ["pending", "rework"] do
      abort!({:illegal_transition, task.status, "claimed"})
    end

    generation = task.claim_generation + 1

    exec!(
      db,
      """
      UPDATE tasks SET status = 'claimed', owner = 'implementer', claim_generation = ?,
        lease_until = ?, updated_at = ? WHERE id = ?
      """,
      [generation, lease_until(), now(), @task_id]
    )

    event!(db, "task_claimed", %{owner: "implementer", generation: generation})
    %{"action" => "assign_implementer", "generation" => generation}
  end

  defp apply_action!(
         db,
         :implementer,
         %{"type" => "submit_candidate", "source" => source},
         generation,
         _evidence
       )
       when is_binary(source) do
    assert_current_claim!(db, :implementer, generation)
    digest = digest(source)
    candidate_id = "candidate-#{generation}-#{String.slice(digest, 0, 10)}"

    exec!(
      db,
      """
      INSERT OR IGNORE INTO candidates
        (id, task_id, claim_generation, source, diff, digest, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, 'ready', ?)
      """,
      [candidate_id, @task_id, generation, source, Section9.Fixture.diff(source), digest, now()]
    )

    exec!(
      db,
      "UPDATE tasks SET status = 'candidate_ready', candidate_id = ?, updated_at = ? WHERE id = ?",
      [candidate_id, now(), @task_id]
    )

    event!(db, "candidate_ready", %{candidate_id: candidate_id, generation: generation})
    %{"action" => "submit_candidate", "candidate_id" => candidate_id, "digest" => digest}
  end

  defp apply_action!(db, :evaluator, %{"type" => "evaluate_candidate"}, generation, evidence)
       when is_map(evidence) do
    task = task_map(db)
    assert_generation!(task, generation)

    unless task.status == "candidate_ready" do
      abort!({:illegal_transition, task.status, "evaluating"})
    end

    evaluation_id = "evaluation-#{System.unique_integer([:positive])}"
    passed = Map.get(evidence, :passed, Map.get(evidence, "passed", false))
    next_status = if passed, do: "passed", else: "rework"

    exec!(db, "UPDATE tasks SET status = 'evaluating', updated_at = ? WHERE id = ?", [
      now(),
      @task_id
    ])

    exec!(
      db,
      "INSERT INTO evaluations VALUES (?, ?, ?, ?, ?)",
      [evaluation_id, task.candidate_id, if(passed, do: 1, else: 0), encode(evidence), now()]
    )

    exec!(
      db,
      "UPDATE tasks SET status = ?, evaluation_id = ?, updated_at = ? WHERE id = ?",
      [next_status, evaluation_id, now(), @task_id]
    )

    event!(db, "evaluation_recorded", %{
      evaluation_id: evaluation_id,
      candidate_id: task.candidate_id,
      passed: passed
    })

    %{"action" => "evaluate_candidate", "evaluation_id" => evaluation_id, "passed" => passed}
  end

  defp apply_action!(db, :evaluator, %{"type" => "request_rework"}, generation, evidence) do
    apply_action!(
      db,
      :evaluator,
      %{"type" => "evaluate_candidate"},
      generation,
      evidence || %{passed: false}
    )
  end

  defp apply_action!(db, :lead, %{"type" => "close_mission"}, generation, _evidence) do
    task = task_map(db)
    assert_generation!(task, generation)

    unless task.status == "passed" do
      abort!({:evaluation_required, task.status})
    end

    exec!(db, "UPDATE tasks SET status = 'closed', updated_at = ? WHERE id = ?", [now(), @task_id])

    exec!(db, "UPDATE missions SET status = 'closed', closed_at = ? WHERE id = ?", [
      now(),
      @mission_id
    ])

    event!(db, "mission_closed", %{evaluation_id: task.evaluation_id})
    %{"action" => "close_mission", "evaluation_id" => task.evaluation_id}
  end

  defp apply_action!(_db, role, action, _generation, _evidence) do
    abort!({:action_not_allowed, role, action["type"]})
  end

  defp commit_actor_state!(db, role, next_state) do
    revision =
      scalar(db, "SELECT revision + 1 FROM actor_states WHERE role = ?", [to_string(role)])

    exec!(
      db,
      "UPDATE actor_states SET revision = ?, state_json = ?, updated_at = ? WHERE role = ?",
      [revision, encode(next_state), now(), to_string(role)]
    )

    revision
  end

  defp assert_current_claim!(db, role, generation) do
    task = task_map(db)
    assert_generation!(task, generation)

    unless task.owner == to_string(role) and task.status == "claimed" do
      abort!({:claim_not_owned, role, task.owner, task.status})
    end
  end

  defp assert_generation!(task, generation) do
    if task.claim_generation != generation do
      abort!({:stale_generation, generation, task.claim_generation})
    end
  end

  defp assert_budget!(db) do
    [used, budget] =
      row(db, "SELECT pulses_used, pulse_budget FROM missions WHERE id = ?", [@mission_id])

    if used >= budget, do: abort!(:mission_budget_exhausted)
  end

  defp seed(db, opts) do
    budget =
      Keyword.get(opts, :mission_budget, Application.get_env(:section9, :mission_budget, 12))

    transaction(db, fn db ->
      for table <-
            ~w(events effects evaluations candidates pulses actor_skills actor_states tasks missions) do
        exec!(db, "DELETE FROM #{table}", [])
      end

      now = now()

      exec!(db, "INSERT INTO missions VALUES (?, 'active', ?, 0, ?, NULL)", [
        @mission_id,
        budget,
        now
      ])

      exec!(
        db,
        "INSERT INTO tasks VALUES (?, ?, ?, 'pending', NULL, 0, NULL, NULL, NULL, ?)",
        [@task_id, @mission_id, "Repair cancellation and late-result handling", now]
      )

      Enum.each(Section9.RolePolicy.roles(), fn role ->
        exec!(
          db,
          "INSERT INTO actor_states VALUES (?, 0, ?, '[]', ?)",
          [to_string(role), encode(BoundedState.initial(role)), now]
        )
      end)

      event!(db, "mission_started", %{mission_id: @mission_id, task_id: @task_id})

      if baseline = Keyword.get(opts, :baseline) do
        event!(db, "failing_baseline_recorded", baseline)
      end

      :ok
    end)
  end

  defp build_context(db, role) do
    snapshot = build_snapshot(db)
    actor = Enum.find(snapshot.actors, &(&1.role == to_string(role)))

    %{
      role: role,
      mission: snapshot.mission,
      task: snapshot.task,
      actor: actor,
      candidate: snapshot.candidate,
      evaluation: snapshot.evaluation,
      recent_events: Enum.take(snapshot.events, -8),
      broken_source: Section9.Fixture.broken_source(),
      acceptance_contract: Section9.Fixture.acceptance_contract()
    }
  end

  defp build_snapshot(db) do
    [mission_id, mission_status, pulse_budget, pulses_used, started_at, closed_at] =
      row(
        db,
        "SELECT id, status, pulse_budget, pulses_used, started_at, closed_at FROM missions LIMIT 1",
        []
      )

    task = task_map(db)

    candidate =
      case task.candidate_id &&
             row(
               db,
               "SELECT id, claim_generation, source, diff, digest, status, created_at FROM candidates WHERE id = ?",
               [task.candidate_id]
             ) do
        [id, generation, source, diff, digest, status, created_at] ->
          %{
            id: id,
            claim_generation: generation,
            source: source,
            diff: diff,
            digest: digest,
            status: status,
            created_at: created_at
          }

        _ ->
          nil
      end

    evaluation =
      case task.evaluation_id &&
             row(
               db,
               "SELECT id, candidate_id, passed, evidence_json, created_at FROM evaluations WHERE id = ?",
               [task.evaluation_id]
             ) do
        [id, candidate_id, passed, evidence, created_at] ->
          %{
            id: id,
            candidate_id: candidate_id,
            passed: passed == 1,
            evidence: decode(evidence),
            created_at: created_at
          }

        _ ->
          nil
      end

    skills =
      query(
        db,
        "SELECT role, name, root_digest, resources_json, loaded_at FROM actor_skills ORDER BY role, name",
        []
      )
      |> Enum.map(fn [role, name, digest, resources, loaded_at] ->
        %{
          role: role,
          name: name,
          root_digest: digest,
          resources: decode(resources),
          loaded_at: loaded_at
        }
      end)

    actors =
      query(
        db,
        "SELECT role, revision, state_json, memory_json, updated_at FROM actor_states ORDER BY role",
        []
      )
      |> Enum.map(fn [role, revision, state_json, memory_json, updated_at] ->
        %{
          role: role,
          revision: revision,
          state: decode(state_json),
          memory: decode(memory_json),
          skills: Enum.filter(skills, &(&1.role == role)),
          updated_at: updated_at
        }
      end)

    %{
      mission: %{
        id: mission_id,
        status: mission_status,
        pulse_budget: pulse_budget,
        pulses_used: pulses_used,
        started_at: started_at,
        closed_at: closed_at
      },
      task: task,
      candidate: candidate,
      evaluation: evaluation,
      actors: actors,
      events: event_rows(db),
      pulses: pulse_rows(db)
    }
  end

  defp task_map(db) do
    [
      id,
      mission_id,
      title,
      status,
      owner,
      generation,
      lease_until,
      candidate_id,
      evaluation_id,
      updated_at
    ] =
      row(
        db,
        "SELECT id, mission_id, title, status, owner, claim_generation, lease_until, candidate_id, evaluation_id, updated_at FROM tasks LIMIT 1",
        []
      )

    %{
      id: id,
      mission_id: mission_id,
      title: title,
      status: status,
      owner: owner,
      claim_generation: generation,
      lease_until: lease_until,
      candidate_id: candidate_id,
      evaluation_id: evaluation_id,
      updated_at: updated_at
    }
  end

  defp event_rows(db) do
    query(db, "SELECT seq, type, data_json, created_at FROM events ORDER BY seq", [])
    |> Enum.map(fn [seq, type, data, created_at] ->
      %{seq: seq, type: type, data: decode(data), created_at: created_at}
    end)
  end

  defp pulse_rows(db) do
    query(
      db,
      "SELECT id, role, number, input_json, state_before_json, state_after_json, output_json, stream_text, status, started_at, finished_at FROM pulses ORDER BY number",
      []
    )
    |> Enum.map(fn [
                     id,
                     role,
                     number,
                     input,
                     before,
                     after_state,
                     output,
                     stream,
                     status,
                     started,
                     finished
                   ] ->
      %{
        id: id,
        role: role,
        number: number,
        input: decode(input),
        state_before: decode(before),
        state_after: decode(after_state),
        output: decode(output),
        stream_text: stream,
        status: status,
        started_at: started,
        finished_at: finished
      }
    end)
  end

  defp event!(db, type, data) do
    exec!(
      db,
      "INSERT INTO events (mission_id, type, data_json, created_at) VALUES (?, ?, ?, ?)",
      [@mission_id, type, encode(data), now()]
    )
  end

  defp migrate(db) do
    Sqlite3.execute(
      db,
      """
      PRAGMA journal_mode = WAL;
      PRAGMA foreign_keys = ON;
      CREATE TABLE IF NOT EXISTS missions (
        id TEXT PRIMARY KEY, status TEXT NOT NULL, pulse_budget INTEGER NOT NULL,
        pulses_used INTEGER NOT NULL, started_at TEXT NOT NULL, closed_at TEXT
      );
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY, mission_id TEXT NOT NULL, title TEXT NOT NULL, status TEXT NOT NULL,
        owner TEXT, claim_generation INTEGER NOT NULL, lease_until TEXT, candidate_id TEXT,
        evaluation_id TEXT, updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS actor_states (
        role TEXT PRIMARY KEY, revision INTEGER NOT NULL, state_json TEXT NOT NULL,
        memory_json TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS actor_skills (
        role TEXT NOT NULL, name TEXT NOT NULL, root_digest TEXT NOT NULL,
        resources_json TEXT NOT NULL, loaded_at TEXT NOT NULL,
        PRIMARY KEY(role, name)
      );
      CREATE TABLE IF NOT EXISTS pulses (
        id TEXT PRIMARY KEY, mission_id TEXT NOT NULL, role TEXT NOT NULL, number INTEGER NOT NULL,
        input_json TEXT NOT NULL, state_before_json TEXT NOT NULL, state_after_json TEXT NOT NULL,
        output_json TEXT NOT NULL, stream_text TEXT NOT NULL, status TEXT NOT NULL,
        started_at TEXT NOT NULL, finished_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS candidates (
        id TEXT PRIMARY KEY, task_id TEXT NOT NULL, claim_generation INTEGER NOT NULL,
        source TEXT NOT NULL, diff TEXT NOT NULL, digest TEXT NOT NULL, status TEXT NOT NULL,
        created_at TEXT NOT NULL, UNIQUE(task_id, claim_generation, digest)
      );
      CREATE TABLE IF NOT EXISTS evaluations (
        id TEXT PRIMARY KEY, candidate_id TEXT NOT NULL, passed INTEGER NOT NULL,
        evidence_json TEXT NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS effects (
        idempotency_key TEXT PRIMARY KEY, role TEXT NOT NULL, kind TEXT NOT NULL,
        status TEXT NOT NULL, request_json TEXT NOT NULL, receipt_json TEXT, created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, mission_id TEXT NOT NULL, type TEXT NOT NULL,
        data_json TEXT NOT NULL, created_at TEXT NOT NULL
      );
      """
    )
  end

  defp transaction(db, fun) do
    :ok = Sqlite3.execute(db, "BEGIN IMMEDIATE")

    try do
      result = fun.(db)
      :ok = Sqlite3.execute(db, "COMMIT")
      result
    rescue
      error ->
        _ = Sqlite3.execute(db, "ROLLBACK")
        reraise error, __STACKTRACE__
    catch
      {:ledger_abort, reason} ->
        _ = Sqlite3.execute(db, "ROLLBACK")
        {:error, reason}
    end
  end

  defp exec!(db, sql, params) do
    {:ok, statement} = Sqlite3.prepare(db, sql)

    try do
      :ok = Sqlite3.bind(statement, params)

      case Sqlite3.step(db, statement) do
        :done -> :ok
        {:error, reason} -> abort!({:sqlite, reason})
        other -> abort!({:unexpected_sql_result, other})
      end
    after
      Sqlite3.release(db, statement)
    end
  end

  defp query(db, sql, params) do
    {:ok, statement} = Sqlite3.prepare(db, sql)

    try do
      :ok = Sqlite3.bind(statement, params)
      {:ok, rows} = Sqlite3.fetch_all(db, statement)
      rows
    after
      Sqlite3.release(db, statement)
    end
  end

  defp row(db, sql, params), do: query(db, sql, params) |> List.first()
  defp scalar(db, sql, params), do: row(db, sql, params) |> List.first()
  defp abort!(reason), do: throw({:ledger_abort, reason})
  defp encode(value), do: Jason.encode!(value)
  defp decode(value), do: Jason.decode!(value, keys: :atoms)
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp lease_until do
    DateTime.utc_now()
    |> DateTime.add(Application.get_env(:section9, :lease_ms, 60_000), :millisecond)
    |> DateTime.to_iso8601()
  end

  defp digest(source), do: :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

  defp publish_if_committed({:error, _}), do: :ok

  defp publish_if_committed(_result) do
    Phoenix.PubSub.broadcast(Section9.PubSub, "section9:ledger", :ledger_changed)
  end
end
