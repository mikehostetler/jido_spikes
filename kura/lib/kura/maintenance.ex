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
  @review "cedar/review"
  @steps ["failure", "new_head", "stale_pass", "pass"]
  alias Kura.Playbooks
  alias Kura.Playbooks.{Fixtures, Runner, Storage, Triage}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Kura.PubSub, @topic)

  def current do
    MaintenanceCase
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!()
  end

  def pending(nil), do: []

  def pending(%{id: id, state: state}) do
    completed =
      for %{"evidence" => %{"pulse_id" => id}} <- state["events"], into: MapSet.new(), do: id

    events =
      for entry <- Inbox.scoped_events(@cedar, id), not MapSet.member?(completed, entry.id) do
        %{"id" => entry.id, "type" => entry.kind, "payload" => entry.payload}
      end

    Enum.uniq_by(Map.get(state, "inbox", []) ++ events, & &1["id"])
  end

  def next_fixture(nil), do: Fixtures.snapshot("failure")

  def next_fixture(%{state: state} = record) do
    cond do
      pending(record) != [] -> nil
      state["phase"] == "closed" -> Fixtures.snapshot("failure")
      state["phase"] in ["waiting_review", "blocked"] -> nil
      true -> Fixtures.snapshot(Enum.find(@steps, &(&1 not in state["fixtures"])))
    end
  end

  def apply_fixture(id), do: GenServer.call(__MODULE__, {:fixture, id}, 10_000)

  def commit_pulse(entry, result, trace) do
    GenServer.call(__MODULE__, {:commit_pulse, entry, result, trace}, 20_000)
  end

  @impl true
  def init(nil) do
    if Application.get_env(:kura, :recover_cells_on_boot, true) do
      {:ok, nil, {:continue, :recover}}
    else
      {:ok, nil}
    end
  end

  @impl true
  def handle_continue(:recover, state) do
    record = recover_legacy_inbox(current())

    schedule_review(record)

    if pending(record) != [], do: wake_cedar()
    {:noreply, state}
  end

  def fixture_review_available?(%{state: %{"phase" => "waiting_review", "playbook" => work}}) do
    work["manual_review"] == true and not review_requested?(work)
  end

  def fixture_review_available?(_record), do: false

  defp review_requested?(work),
    do: Map.get(work, "review_requested", work["manual_review"] != true)

  @impl true
  def handle_call({:fixture, id}, _from, state) do
    record = current()

    result =
      case {id, next_fixture(record)} do
        {"failure_sparse", %{"id" => "failure"}} ->
          accept(record, Fixtures.sparse())

        {^id, %{"id" => ^id} = snapshot} ->
          accept(record, snapshot)

        {"review_reply", _} ->
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
  def handle_info({:dispatch_review, id}, state) do
    case current() do
      %{id: ^id, state: %{"phase" => "waiting_review", "playbook" => work}} = record ->
        if review_requested?(work), do: dispatch_review(record, work)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  defp dispatch_review(%{id: id, state: state} = record, work) do
    [failure | _] = state["events"]
    correlation = Map.take(work, ["run_id", "wait_id", "question"])

    result =
      with {:ok, cedar_receipt, %{"head" => head} = reply} <-
             Review.inspect_failure(@cedar, @review, id, failure["evidence"], correlation),
           true <- head == state["original_head"] do
        accept_review(record, work, reply, cedar_receipt)
      else
        false -> {:error, :unmatched_review_reply}
        {:error, _} = error -> error
      end

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> review_failed(record, work, reason)
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

  defp accept(_record, %{"id" => "failure", "head" => head} = snapshot) do
    %{
      "phase" => "waiting_ci",
      "original_head" => head,
      "current_head" => head,
      "fixtures" => ["failure"],
      "triage_version" => version_id(),
      "events" => []
    }
    |> add_event("CI", "CI failed on the original commit.", snapshot)
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
    case current() do
      %{id: ^case_id} = record ->
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
        case tool_result(trace, "propose_playbook_edit") do
          %{} = change -> {learn_method(state, case_id, pulse, change), result}
          _ -> {state, result}
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

  defp learn_method(state, case_id, pulse, change) do
    evidence = %{"case_id" => case_id, "pulse_id" => pulse["id"]}

    with {:ok, version} <- Playbooks.get(@cedar, state["triage_version"]),
         {:ok, candidate} <- Playbooks.proposal(version, pulse["id"], evidence, change) do
      add_event(state, "Cedar", "Saved a playbook candidate.", %{"candidate_id" => candidate.id})
    else
      error ->
        add_event(state, "Cedar", "The playbook proposal was rejected.", %{
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
         :ok <- enqueue_events(saved.id, events) do
      {:ok, saved}
    end
  end

  defp notify_and_wake(result) do
    result
    |> notify()
    |> tap(fn
      {:ok, _} -> wake_cedar()
      _ -> :ok
    end)
  end

  defp recover_legacy_inbox(%{state: %{"inbox" => pulses}} = record) do
    events = Enum.map(pulses, &{&1["type"], &1["payload"], &1["id"]})

    case Repo.transact(fn ->
           with :ok <- enqueue_events(record.id, events),
                do: save(Map.delete(record.state, "inbox"), record)
         end)
         |> notify() do
      {:ok, updated} -> updated
      {:error, reason} -> raise "Could not recover the maintenance inbox: #{inspect(reason)}"
    end
  end

  defp recover_legacy_inbox(record), do: record

  defp enqueue_events(case_id, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      {type, payload, id} =
        case event do
          {type, payload} -> {type, payload, Ash.UUID.generate()}
          {type, payload, id} -> {type, payload, id}
        end

      case Inbox.enqueue(@cedar, type, payload, scope_id: case_id, id: id) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp wake_cedar do
    case Kura.Cells.wake(@cedar) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Could not wake Cedar: #{inspect(reason)}")
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
