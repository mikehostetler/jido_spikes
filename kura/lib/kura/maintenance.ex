defmodule Kura.Maintenance do
  @moduledoc "Cedar's maintenance case, CI gate, and handoff to Review."
  use GenServer
  require Logger

  alias Kura.Cell.{Inbox, Journal}
  alias Kura.Maintenance.{Pulse, Review}
  alias Kura.Repo
  alias Kura.Work.{Entry, MaintenanceCase}

  @topic "maintenance"
  @cedar "cedar"
  @workers ~w(cedar/review cedar/review-2 cedar/review-3)
  @pool_size 10
  @steps ["failure", "new_head", "stale_pass", "pass"]
  alias Kura.Playbooks
  alias Kura.Playbooks.{Fixtures, Runner, Storage, Triage}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Kura.PubSub, @topic)

  def workers, do: @workers
  def worker_id(%{state: state}), do: Map.get(state, "worker", @cedar)

  def fetch(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Ash.get!(MaintenanceCase, id, not_found_error?: false)
      :error -> nil
    end
  end

  def fetch(_), do: nil

  def portfolio do
    cases = Ash.read!(MaintenanceCase)

    case Enum.max_by(Enum.filter(cases, & &1.state["pool_id"]), & &1.inserted_at, DateTime, fn ->
           nil
         end) do
      nil ->
        []

      latest ->
        cases
        |> Enum.filter(&(&1.state["pool_id"] == latest.state["pool_id"]))
        |> Enum.sort_by(& &1.state["slot"])
    end
  end

  def current do
    MaintenanceCase
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!()
  end

  def pending(nil), do: []

  def pending(%{id: id, state: state} = record) do
    completed =
      for %{"evidence" => %{"pulse_id" => id}} <- state["events"], into: MapSet.new(), do: id

    events =
      for entry <- Inbox.scoped_events(worker_id(record), id),
          not MapSet.member?(completed, entry.id) do
        %{"id" => entry.id, "type" => entry.kind, "payload" => entry.payload}
      end

    Enum.uniq_by(Map.get(state, "inbox", []) ++ events, & &1["id"])
  end

  def next_fixture(record), do: next_fixture(record, pending(record))

  def next_fixture(nil, _pending), do: Fixtures.snapshot("failure")

  def next_fixture(%{state: state}, pending) do
    cond do
      pending != [] ->
        nil

      state["phase"] == "closed" and state["pool_id"] ->
        nil

      state["phase"] == "closed" ->
        Fixtures.snapshot("failure")

      state["phase"] in ["waiting_review", "blocked"] ->
        nil

      true ->
        @steps
        |> Enum.find(&(&1 not in state["fixtures"]))
        |> Fixtures.snapshot(state["scope"])
    end
  end

  def apply_fixture(id, case_id \\ nil),
    do: GenServer.call(__MODULE__, {:fixture, id, case_id}, 10_000)

  def open_pool, do: GenServer.call(__MODULE__, :open_pool, 10_000)

  def commit_pulse(entry, result, trace) do
    GenServer.call(__MODULE__, {:commit_pulse, entry, result, trace}, 20_000)
  end

  @impl true
  def init(nil) do
    if Application.get_env(:kura, :recover_cells_on_boot, true) do
      {:ok, %{}, {:continue, :recover}}
    else
      {:ok, %{}}
    end
  end

  @impl true
  def handle_continue(:recover, state) do
    for record <- Ash.read!(MaintenanceCase) do
      record = recover_legacy_inbox(record)
      schedule_review(record)
      if pending(record) != [], do: wake_worker(record)
    end

    {:noreply, state}
  end

  def fixture_review_available?(%{state: %{"phase" => "waiting_review", "playbook" => work}}) do
    work["manual_review"] == true and not review_requested?(work)
  end

  def fixture_review_available?(_record), do: false

  defp review_requested?(work),
    do: Map.get(work, "review_requested", work["manual_review"] != true)

  @impl true
  def handle_call(:open_pool, _from, state) do
    result =
      if Enum.any?(portfolio(), &(&1.state["phase"] != "closed" or pending(&1) != [])) do
        {:error, :pool_already_open}
      else
        start_pool()
      end

    {:reply, result, state}
  end

  def handle_call({:fixture, id, case_id}, _from, state) do
    record = if case_id, do: fetch(case_id), else: current()

    result =
      case {id, next_fixture(record), is_nil(case_id) or not is_nil(record)} do
        {"failure_sparse", %{"id" => "failure"}, true} ->
          accept(record, Fixtures.sparse())

        {^id, %{"id" => ^id} = snapshot, true} ->
          accept(record, snapshot)

        {"review_reply", _, true} ->
          request_manual_review(record)

        _ ->
          {:error, :fixture_out_of_order}
      end

    {:reply, result, state}
  end

  def handle_call({:commit_pulse, entry, result, trace}, _from, state) do
    {:reply, complete_pulse(entry, result, trace), state}
  end

  defp request_manual_review(record) do
    if fixture_review_available?(record) do
      case save(put_in(record.state, ["playbook", "review_requested"], true), record)
           |> notify() do
        {:ok, updated} = result ->
          schedule_review(updated)
          result

        error ->
          error
      end
    else
      {:error, :fixture_out_of_order}
    end
  end

  defp schedule_review(record, delay \\ 0)

  defp schedule_review(
         %{id: id, state: %{"phase" => "waiting_review", "playbook" => work}},
         delay
       ) do
    if review_requested?(work), do: Process.send_after(self(), {:dispatch_review, id}, delay)
  end

  defp schedule_review(_record, _delay), do: :ok

  @impl true
  def handle_info({:dispatch_review, id}, active) do
    case fetch(id) do
      %{state: %{"phase" => "waiting_review", "playbook" => work}} = record ->
        {:noreply,
         if(review_requested?(work), do: start_review(record, work, active), else: active)}

      _ ->
        {:noreply, active}
    end
  end

  def handle_info({ref, result}, active) when is_reference(ref) and is_map_key(active, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_review(ref, result, active)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, active) when is_map_key(active, ref) do
    {:noreply, finish_review(ref, {:error, reason}, active)}
  end

  defp start_review(record, work, active) do
    worker = review_worker(record)

    case Enum.find(Map.values(active), fn {_id, assigned} -> assigned == worker end) do
      {id, ^worker} when id == record.id ->
        active

      {_id, ^worker} ->
        schedule_review(record, 200)
        active

      nil ->
        [failure | _] = record.state["events"]
        correlation = Map.take(work, ["run_id", "wait_id", "question"])

        task =
          Task.Supervisor.async_nolink(Kura.Maintenance.ReviewSupervisor, fn ->
            Review.inspect_failure(@cedar, worker, record.id, failure["evidence"], correlation)
          end)

        Map.put(active, task.ref, {record.id, worker})
    end
  end

  defp finish_review(ref, result, active) do
    {{id, _worker}, active} = Map.pop!(active, ref)

    case fetch(id) do
      %{state: %{"phase" => "waiting_review", "playbook" => work, "original_head" => head}} =
          record ->
        case result do
          {:ok, receipt, %{"head" => ^head} = reply} ->
            case accept_review(record, work, reply, receipt) do
              {:ok, _} -> :ok
              {:error, reason} -> review_failed(record, work, reason)
            end

          {:ok, _, _} ->
            review_failed(record, work, :unmatched_review_reply)

          {:error, reason} ->
            review_failed(record, work, reason)
        end

      _ ->
        :ok
    end

    active
  end

  defp review_worker(record) do
    case worker_id(record) do
      @cedar -> hd(@workers)
      worker -> worker
    end
  end

  defp accept_review(record, work, reply, cedar_receipt) do
    Repo.transact(fn ->
      with {:ok, resumed} <- resume_review(record.state, reply) do
        resumed
        |> Map.put("phase", "waiting_ci")
        |> add_event("Cedar", "Asked Review to inspect the failure.", %{
          "head" => reply["head"],
          "receipt" => cedar_receipt,
          "evidence" => work["question"]
        })
        |> add_event("Review", reply["finding"], reply)
        |> persist_and_enqueue(record, [{"review_reply", reply}])
      end
    end)
    |> notify_and_wake()
  end

  defp review_failed(record, work, reason) do
    attempts = Map.get(work, "review_attempts", 0) + 1
    terminal = attempts >= 3 or reason in [:unmatched_review_reply, :wrong_parent]
    updated = put_in(record.state, ["playbook", "review_attempts"], attempts)

    updated =
      if terminal,
        do: blocked(updated, "Review could not complete.", reason),
        else: add_event(updated, "Cedar", "Review will retry.", %{"error" => inspect(reason)})

    case save(updated, record) |> notify() do
      {:ok, saved} ->
        schedule_review(saved, 1_000)

      {:error, error} ->
        Logger.warning("Could not save Review result: #{inspect(error)}")
        schedule_review(record, 1_000)
    end
  end

  defp resume_review(
         %{"playbook" => %{"run_id" => run_id, "wait_id" => wait_id} = work} = state,
         review
       ) do
    with %{"run_id" => ^run_id, "wait_id" => ^wait_id} <- review,
         {:ok, run} <- Storage.get_run(run_id),
         {:ok, finished} <- Runner.resume(run, wait_id, Map.take(review, ["finding"])) do
      {:ok, put_in(state["playbook"], Map.put(work, "result", Triage.result(finished)))}
    else
      {:error, _} = error -> error
      _ -> {:error, :unmatched_review_reply}
    end
  end

  defp resume_review(state, _review), do: {:ok, state}

  defp start_pool do
    pool_id = Ash.UUID.generate()
    version = version_id()

    Repo.transact(fn ->
      Enum.reduce_while(1..@pool_size, {:ok, []}, fn slot, {:ok, records} ->
        worker = Enum.at(@workers, rem(slot - 1, length(@workers)))
        scope = "#{pool_id}:#{slot}"

        failure =
          if slot <= length(@workers),
            do: Fixtures.sparse(scope),
            else: Fixtures.snapshot("failure", scope)

        attrs = %{"pool_id" => pool_id, "slot" => slot, "worker" => worker, "scope" => scope}

        case persist_and_enqueue(open_state(failure, version, attrs), nil, [
               {"ci_snapshot", failure}
             ]) do
          {:ok, record} -> {:cont, {:ok, [record | records]}}
          error -> {:halt, error}
        end
      end)
    end)
    |> case do
      {:ok, records} ->
        records |> Enum.uniq_by(&worker_id/1) |> Enum.each(&wake_worker/1)
        notify({:ok, Enum.reverse(records)})

      error ->
        error
    end
  end

  defp open_state(%{"head" => head} = snapshot, version, attrs) do
    %{
      "phase" => "waiting_ci",
      "original_head" => head,
      "current_head" => head,
      "fixtures" => ["failure"],
      "triage_version" => version,
      "events" => []
    }
    |> Map.merge(attrs)
    |> add_event("CI", "CI failed on the original commit.", snapshot)
  end

  defp accept(_record, %{"id" => "failure"} = snapshot) do
    snapshot
    |> open_state(version_id(), %{})
    |> save_and_enqueue(nil, [{"ci_snapshot", snapshot}])
  end

  defp accept(record, snapshot) do
    state = record.state
    head = if snapshot["id"] == "new_head", do: snapshot["head"], else: state["current_head"]
    {phase, decision} = ci_gate(snapshot, head, state["original_head"])

    updated =
      state
      |> Map.put("current_head", head)
      |> Map.put("phase", phase)
      |> Map.update!("fixtures", &(&1 ++ [snapshot["id"]]))
      |> add_event("CI", snapshot["label"], snapshot)
      |> add_event("CI gate", decision, %{"head" => head})

    events = [{"ci_snapshot", snapshot}]

    events =
      if phase == "closed",
        do: events ++ [{"case_closed", %{"passing_check" => snapshot}}],
        else: events

    save_and_enqueue(updated, record, events)
  end

  def ci_gate(snapshot, head, original_head) do
    cond do
      snapshot["status"] != "passed" ->
        {"waiting_ci", "Wait for CI on the new commit."}

      snapshot["head"] != head or snapshot["check_head"] != head ->
        {"waiting_ci", "Keep the case open. This check ran on a different commit."}

      head == original_head ->
        {"waiting_ci", "Keep the case open. This is the original commit."}

      true ->
        {"closed", "Close the case. CI passed on the new head."}
    end
  end

  defp version_id do
    {:ok, _} = Triage.seed()
    Playbooks.active(@cedar, "ci_triage").id
  end

  defp complete_pulse(entry, result, trace) do
    case Ash.get(Entry, entry.id) do
      {:ok, %{status: "queued"} = persisted} -> commit_queued_pulse(persisted, result, trace)
      other -> other
    end
  end

  defp commit_queued_pulse(%{scope_id: case_id} = entry, result, trace) do
    case fetch(case_id) do
      %{} = record ->
        pulse = %{"id" => entry.id, "type" => entry.kind, "payload" => entry.payload}

        result =
          Repo.transact(fn ->
            {updated, result} = apply_playbook_intent(record.state, case_id, pulse, result, trace)

            updated =
              add_event(updated, "Cedar", "Cognitive pulse", %{
                "pulse_id" => entry.id,
                "trigger" => entry.kind,
                "trace" => trace
              })

            with {:ok, saved} <- save(updated, record),
                 {:ok, finished} <- Journal.resolve(entry, result, trace) do
              {:ok, {saved, finished}}
            end
          end)

        case result do
          {:ok, {saved, finished}} ->
            notify({:ok, saved})
            schedule_review(saved)
            {:ok, finished}

          {:error, _} ->
            result
        end

      _ ->
        Journal.resolve(entry, {:error, :case_unavailable}, trace)
    end
  end

  defp apply_playbook_intent(state, case_id, pulse, result, trace) do
    case Pulse.purpose(state, pulse["type"], pulse["payload"]) do
      :select ->
        case result do
          {:error, reason} ->
            {blocked(state, "Cedar could not assess the failure.", reason), result}

          {:ok, _} ->
            if trace["status"] == "local_demo" or tool_result(trace, "use_playbook") do
              case run_playbook(state, pulse) do
                {:ok, updated} ->
                  {updated, result}

                {:error, reason} = error ->
                  {blocked(state, "Playbook could not complete triage.", reason), error}
              end
            else
              {state, result}
            end
        end

      :learn ->
        case trace do
          %{"learning" => %{"change" => %{} = change} = learning} ->
            {learn_method(state, case_id, pulse, change, learning), result}

          _ ->
            {state, result}
        end

      nil ->
        {state, result}
    end
  end

  defp run_playbook(state, pulse) do
    with {:ok, version} <- Playbooks.get(@cedar, state["triage_version"]),
         {:ok, run} <- Runner.start(version, pulse["type"], pulse["payload"], pulse["id"]) do
      work = %{
        "version" => version.revision,
        "run_id" => run.id,
        "result" => Triage.result(run)
      }

      work =
        case version.evidence do
          %{"source" => "tune", "pulse_id" => learning_id, "case_id" => learning_case} ->
            Map.put(work, "learned_from", %{
              "case_id" => learning_case,
              "pulse_id" => learning_id,
              "version_id" => version.id
            })

          _ ->
            work
        end

      case {run.status, Runner.open_wait(run)} do
        {:succeeded, nil} ->
          {:ok,
           state
           |> Map.put("playbook", work)
           |> add_event("Loom", "Triage completed using CI evidence.", work)}

        {:waiting, %{} = wait} ->
          manual = pulse["payload"]["assertion_complete"] == false

          work =
            Map.merge(work, %{
              "wait_id" => wait.id,
              "question" => wait.prompt,
              "manual_review" => manual,
              "review_requested" => not manual
            })

          {:ok,
           state
           |> Map.put("phase", "waiting_review")
           |> Map.put("playbook", work)
           |> add_event("Cedar", "Saved a Review request.", Map.take(work, ["run_id", "wait_id"]))}

        _ ->
          {:error, :unexpected_triage_state}
      end
    end
  end

  defp blocked(state, message, reason) do
    state
    |> Map.put("phase", "blocked")
    |> add_event("Cedar", message, %{"error" => inspect(reason)})
  end

  defp learn_method(state, case_id, pulse, change, learning) do
    evidence =
      learning
      |> Map.take(["observations", "scores"])
      |> Map.merge(%{"case_id" => case_id, "pulse_id" => pulse["id"], "source" => "tune"})

    with {:ok, version} <- Playbooks.get(@cedar, state["triage_version"]),
         {:ok, candidate} <- Playbooks.proposal(version, pulse["id"], evidence, change) do
      state =
        add_event(state, "Tune", "Saved a playbook candidate.", %{"candidate_id" => candidate.id})

      case Playbooks.replay(@cedar, candidate.id) do
        {:ok, _} ->
          state

        {:error, reason} ->
          add_event(state, "Loom", "Could not replay the candidate on fixtures.", %{
            "error" => inspect(reason)
          })
      end
    else
      error ->
        add_event(state, "Tune", "The playbook proposal was rejected.", %{
          "error" => inspect(error)
        })
    end
  end

  defp tool_result(%{"status" => "completed", "tools" => tools}, name) do
    Enum.find_value(tools, fn
      %{"name" => ^name, "status" => "ok", "result" => result} -> result
      _ -> nil
    end)
  end

  defp tool_result(_trace, _name), do: nil

  defp add_event(state, actor, message, evidence) do
    event = %{
      "actor" => actor,
      "message" => message,
      "evidence" => evidence,
      "at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Map.update!(state, "events", &(&1 ++ [event]))
  end

  defp save_and_enqueue(state, record, events) do
    Repo.transact(fn -> persist_and_enqueue(state, record, events) end)
    |> notify_and_wake()
  end

  defp persist_and_enqueue(state, record, events) do
    with {:ok, saved} <- save(state, record),
         :ok <- enqueue_events(saved, events) do
      {:ok, saved}
    end
  end

  defp notify_and_wake(result) do
    result
    |> notify()
    |> tap(fn
      {:ok, record} -> wake_worker(record)
      _ -> :ok
    end)
  end

  defp recover_legacy_inbox(%{state: %{"inbox" => pulses}} = record) do
    events = Enum.map(pulses, &{&1["type"], &1["payload"], &1["id"]})

    case Repo.transact(fn ->
           with :ok <- enqueue_events(record, events),
                do: save(Map.delete(record.state, "inbox"), record)
         end)
         |> notify() do
      {:ok, updated} -> updated
      {:error, reason} -> raise "Could not recover the maintenance inbox: #{inspect(reason)}"
    end
  end

  defp recover_legacy_inbox(record), do: record

  defp enqueue_events(record, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      {type, payload, id} =
        case event do
          {type, payload} -> {type, payload, Ash.UUID.generate()}
          {type, payload, id} -> {type, payload, id}
        end

      case Inbox.enqueue(worker_id(record), type, payload, scope_id: record.id, id: id) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp wake_worker(record) do
    worker = worker_id(record)

    case Kura.Cells.wake(worker) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Could not wake #{worker}: #{inspect(reason)}")
    end
  end

  defp save(state, nil), do: Ash.create(MaintenanceCase, %{state: state}, action: :open)
  defp save(state, record), do: Ash.update(record, %{state: state}, action: :advance)

  defp notify({:ok, _} = result) do
    Phoenix.PubSub.broadcast(Kura.PubSub, @topic, :maintenance_changed)
    result
  end

  defp notify(result), do: result
end
