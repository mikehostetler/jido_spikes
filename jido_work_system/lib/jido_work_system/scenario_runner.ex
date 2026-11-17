defmodule JidoWorkSystem.ScenarioRunner do
  @moduledoc false

  alias JidoWorkSystem.{Repo, RunSnapshot, Scenarios, Store}
  alias JidoWorkSystem.Model
  alias JidoWorkSystem.Scenarios.Scenario

  @method_types ~w(human llm decision_rule classifier optimizer search htn hybrid)
  @workspace_root "/simulation/workspace"

  def start(scenario_key) do
    with {:ok, scenario} <- Scenarios.fetch(scenario_key),
         {:ok, run} <- Repo.transaction(fn -> create_foundation!(scenario) end) do
      {:ok, run}
    end
  end

  def get(run_id), do: Store.get(Model.ScenarioRun, run_id)

  def latest do
    case Store.last(Model.ScenarioRun) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  def step(run_id, expected_revision) do
    with {:ok, run} <- get(run_id),
         :ok <- step_allowed(run),
         {:ok, scenario} <- Scenarios.fetch(run.scenario_key),
         beat_result <- next_beat(scenario, run.cursor) do
      case beat_result do
        {:beat, beat} ->
          advance(run, expected_revision, scenario, beat)

        {:beat, beat, forced_status} ->
          advance(run, expected_revision, scenario, beat, forced_status)

        other ->
          other
      end
    end
  end

  def choose(run_id, expected_revision, choice) do
    with {:ok, run} <- get(run_id),
         :ok <- choice_allowed(run),
         {:ok, scenario} <- Scenarios.fetch(run.scenario_key),
         {:beat, beat, forced_status} <- Scenario.choose(scenario, run.cursor, choice) do
      advance(run, expected_revision, scenario, beat, forced_status)
    end
  end

  defp next_beat(scenario, cursor) do
    case Scenario.next(scenario, cursor) do
      {:beat, beat} -> {:beat, beat}
      {:beat, beat, status} -> {:beat, beat, status}
      {:choice, _choices} -> {:error, :choice_required}
      :complete -> {:error, :complete}
    end
  end

  defp step_allowed(%{status: "waiting_for_choice"}), do: {:error, :choice_required}

  defp step_allowed(%{status: status}) when status in ["complete", "ended"],
    do: {:error, :complete}

  defp step_allowed(_run), do: :ok

  defp choice_allowed(%{status: "waiting_for_choice"}), do: :ok
  defp choice_allowed(_run), do: {:error, :choice_not_required}

  defp advance(run, expected_revision, scenario, beat, forced_status \\ nil) do
    case Repo.transaction(fn ->
           current = Store.get!(Model.ScenarioRun, run.id)

           if current.revision != expected_revision do
             Repo.rollback(:stale_revision)
           end

           apply_beat!(current, beat)

           next_cursor = current.cursor + 1
           next_status = forced_status || status_for(Scenario.next(scenario, next_cursor))

           Store.update!(current, %{
             cursor: next_cursor,
             revision: current.revision + 1,
             current_beat: Atom.to_string(beat),
             status: Atom.to_string(next_status)
           })
         end) do
      {:ok, updated_run} -> {:ok, updated_run}
      {:error, reason} -> {:error, reason}
    end
  end

  defp status_for({:beat, _beat}), do: :running
  defp status_for({:beat, _beat, _status}), do: :running
  defp status_for({:choice, _choices}), do: :waiting_for_choice
  defp status_for(:complete), do: :complete

  defp create_foundation!(scenario) do
    system =
      Store.create!(Model.WorkSystem, %{
        name: "Mike's Work System",
        purpose: "Help Mike make a clear note about a new app release"
      })

    human =
      Store.create!(Model.HumanActor, %{
        work_system_id: system.id,
        name: "Mike",
        kind: "person who owns the job"
      })

    role =
      Store.create!(Model.Role, %{
        work_system_id: system.id,
        name: "Job owner",
        purpose: "Explain the job and decide when it is done"
      })

    _authority =
      Store.create!(Model.Authority, %{
        work_system_id: system.id,
        holder_id: human.id,
        role_id: role.id,
        name: "Rules for this job",
        scope: "One note about a new app release",
        permitted_actions: ["plan", "write", "revise", "submit"],
        limits: "Do not use the internet. Write only in the safe work area."
      })

    Store.create!(Model.Accountability, %{
      work_system_id: system.id,
      human_actor_id: human.id,
      role_id: role.id,
      subject: "Mike owns the note and says when it is done",
      acceptance_right: true
    })

    parent = create_cell!(system, human, "Main work cell", "delivery")
    _child = create_cell!(system, human, "Writing work cell", "release-note", parent.id)

    workspace =
      Store.create!(Model.Workspace, %{
        work_system_id: system.id,
        name: "Safe work area",
        root: @workspace_root,
        boundary: "The work cell can only write files in this area"
      })

    Store.create!(Model.Tool, %{
      work_system_id: system.id,
      workspace_id: workspace.id,
      name: "Note writer",
      capability: "Write or fix one note",
      allowed_path: @workspace_root <> "/release-note.md"
    })

    Store.create!(Model.Knowledge, %{
      work_system_id: system.id,
      title: "Facts about the new app release",
      content: "The release adds a work simulation. It does not use outside services.",
      provenance: "Facts saved for this story"
    })

    Enum.each(@method_types, fn type ->
      Store.create!(Model.JudgmentMethod, %{
        work_system_id: system.id,
        name: method_name(type),
        method_type: type,
        provider: provider(type),
        deterministic: true
      })
    end)

    Store.create!(Model.ScenarioRun, %{
      work_system_id: system.id,
      scenario_key: scenario.key,
      status: "ready",
      cursor: 0,
      revision: 0,
      current_beat: "ready"
    })
  end

  defp apply_beat!(run, beat) do
    context = context(run)
    sequence = run.cursor + 1

    case beat do
      :request_clarification ->
        simple_event!(
          context,
          sequence,
          "clarification_requested",
          "The work cell asks Mike to make the job clear."
        )

      :clarification_received ->
        simple_event!(
          context,
          sequence,
          "clarification_received",
          "Mike explains the result that he needs."
        )

      :define_task ->
        define_task!(context, sequence)

      :delegate_task ->
        delegate_task!(context, sequence)

      :accept_delegation ->
        accept_delegation!(context, sequence)

      :reject_delegation ->
        reject_delegation!(context, sequence)

      :plan_work ->
        plan_work!(context, sequence)

      :check_authority ->
        check_authority!(context, sequence)

      :facts_missing ->
        simple_event!(
          context,
          sequence,
          "facts_missing",
          "The work cell stops because one fact is missing."
        )

      :provide_facts ->
        provide_facts!(context, sequence)

      :permission_denied ->
        simple_event!(
          context,
          sequence,
          "permission_denied",
          "The work cell stops before it uses an action that is not allowed."
        )

      :grant_permission ->
        grant_permission!(context, sequence)

      :select_draft ->
        select_draft!(context, sequence)

      :write_draft ->
        write_draft!(context, sequence)

      :tool_failed ->
        simple_event!(
          context,
          sequence,
          "tool_failed",
          "The note writer fails. No work is changed."
        )

      :retry_tool ->
        simple_event!(
          context,
          sequence,
          "tool_retry",
          "The work cell checks the rules and tries the note writer again."
        )

      :record_complete_evidence ->
        record_evidence!(context, sequence, :complete)

      :record_incomplete_evidence ->
        record_evidence!(context, sequence, :incomplete)

      :verify_pass ->
        verify_pass!(context, sequence, "The note has all three parts")

      :checker_unavailable ->
        simple_event!(
          context,
          sequence,
          "checker_unavailable",
          "The note waits because the checker is not ready."
        )

      :checker_returns ->
        simple_event!(
          context,
          sequence,
          "checker_ready",
          "The checker is ready and takes the note."
        )

      :verify_fail ->
        verify_fail!(context, sequence)

      :request_revision ->
        request_revision!(context, sequence)

      :rework_judgment ->
        rework_judgment!(context, sequence)

      :revise_draft ->
        revise_draft!(context, sequence)

      :change_job ->
        change_job!(context, sequence)

      :record_revised_evidence ->
        record_evidence!(context, sequence, :complete)

      :verify_revised ->
        verify_pass!(context, sequence, "The fixed note has all three parts")

      :accept_outcome ->
        accept!(context, sequence, "accepted", "Mike checks the note and says the job is done.")

      :accept_after_rework ->
        accept!(
          context,
          sequence,
          "accepted_after_rework",
          "Mike checks the fixed note and says the job is done."
        )

      :cancel_job ->
        close_without_result!(
          context,
          sequence,
          "canceled",
          "job_canceled",
          "Mike cancels the job. The work cell stops."
        )

      :deadline_missed ->
        close_without_result!(
          context,
          sequence,
          "expired",
          "deadline_missed",
          "The deadline passes. The work cell closes the job."
        )

      :delegate_to_specialist ->
        delegate_to_specialist!(context, sequence)

      :specialist_returns ->
        specialist_returns!(context, sequence)

      :stop_after_rework ->
        reject!(context, sequence, "Mike stops the job after the second failed check.")

      :reject_passed_work ->
        reject!(
          context,
          sequence,
          "The note passes its check, but Mike says it no longer helps him."
        )

      :end_run ->
        reject!(context, sequence)
    end
  end

  defp context(run) do
    snapshot = RunSnapshot.build(run)

    %{
      run: run,
      snapshot: snapshot,
      system: snapshot.system,
      human: first!(snapshot.humans),
      role: first!(snapshot.roles),
      authority: first!(snapshot.authorities),
      cell: Enum.find(snapshot.cells, & &1.parent_id),
      task: List.first(snapshot.tasks),
      delegation: List.first(snapshot.delegations),
      work: List.first(snapshot.work),
      methods: Map.new(snapshot.methods, &{&1.method_type, &1}),
      workspace: first!(snapshot.workspaces),
      tool: first!(snapshot.tools),
      mutation: List.last(snapshot.mutations),
      evidence: List.last(snapshot.evidence),
      evaluation: List.last(snapshot.evaluations)
    }
  end

  defp define_task!(context, sequence) do
    task =
      Store.create!(Model.Task, %{
        work_system_id: context.system.id,
        accountable_actor_id: context.human.id,
        title: "Write the app release note",
        purpose: "Tell people what is new and what they need to know",
        required_output:
          "One note with: what changed, what could go wrong, and what people need to do",
        quantity: "One note with three parts",
        quality: "Use the given facts. Make the note short and clear.",
        target_completion_time: ~U[2026-11-18 18:00:00.000000Z],
        resource_limits: "Use the note writer. Do not use the internet.",
        discretion_limits: "The work cell can write the note. Mike must say when it is done.",
        escalation_conditions: "Ask Mike for help if the facts do not match or two checks fail.",
        status: "defined"
      })

    event!(
      context.system,
      task,
      sequence,
      "task_defined",
      "Mike has a job to do. He needs a note with three parts."
    )
  end

  defp delegate_task!(context, sequence) do
    Store.create!(Model.Delegation, %{
      task_id: context.task.id,
      from_actor_id: context.human.id,
      to_cell_id: context.cell.id,
      authority_id: context.authority.id,
      status: "offered",
      terms: "Follow the job rules. Give the finished note to the checker."
    })

    event!(
      context.system,
      context.task,
      sequence,
      "task_delegated",
      "Mike gives the job to the writing work cell."
    )
  end

  defp accept_delegation!(context, sequence) do
    Store.update!(context.delegation, %{status: "accepted"})

    Store.create!(Model.WorkExecution, %{
      task_id: context.task.id,
      work_cell_id: context.cell.id,
      status: "in_progress",
      current_state: %{"phase" => "planning", "revision" => 0}
    })

    Store.update!(context.task, %{status: "in_progress"})

    event!(
      context.system,
      context.task,
      sequence,
      "delegation_accepted",
      "The writing work cell takes the job."
    )
  end

  defp reject_delegation!(context, sequence) do
    Store.update!(context.delegation, %{status: "rejected"})
    Store.update!(context.task, %{status: "declined"})

    event!(
      context.system,
      context.task,
      sequence,
      "delegation_rejected",
      "The work cell says it cannot do this job with its current tools."
    )
  end

  defp plan_work!(context, sequence) do
    judgment!(
      context,
      context.methods["htn"],
      "Make a plan",
      ["write the note", "check the note", "give it back to Mike"],
      "Write, check, and return the note"
    )

    event!(
      context.system,
      context.task,
      sequence,
      "judgment_recorded",
      "The work cell makes a three-step plan: write, check, and return the note."
    )
  end

  defp check_authority!(context, sequence) do
    true = authorized?(context.authority, "write")

    judgment!(
      context,
      context.methods["decision_rule"],
      "Check the job rules",
      ["continue", "stop"],
      "Keep going because the rules allow each step"
    )

    event!(
      context.system,
      context.task,
      sequence,
      "authority_checked",
      "The work cell checks the rules. It is allowed to write the note."
    )
  end

  defp provide_facts!(context, sequence) do
    knowledge = first!(context.snapshot.knowledge)

    Store.update!(knowledge, %{
      content:
        knowledge.content <> " Mike confirms that users do not need to change their settings."
    })

    event!(
      context.system,
      context.task,
      sequence,
      "facts_supplied",
      "Mike supplies the missing fact. The work cell can continue."
    )
  end

  defp grant_permission!(context, sequence) do
    actions = Enum.uniq(context.authority.permitted_actions ++ ["format"])
    Store.update!(context.authority, %{permitted_actions: actions})

    event!(
      context.system,
      context.task,
      sequence,
      "permission_granted",
      "Mike allows one more action for this job."
    )
  end

  defp select_draft!(context, sequence) do
    judgment!(
      context,
      context.methods["llm"],
      "Choose words for the note",
      ["first draft", "second draft"],
      "Use the first draft"
    )

    event!(
      context.system,
      context.task,
      sequence,
      "draft_selected",
      "The work cell chooses the first draft."
    )
  end

  defp write_draft!(context, sequence) do
    mutation!(context, "write", %{"phase" => "planning", "revision" => 0}, %{
      "phase" => "drafted",
      "revision" => 1,
      "path" => context.tool.allowed_path
    })

    event!(
      context.system,
      context.task,
      sequence,
      "mutation_applied",
      "The work cell writes the note."
    )
  end

  defp record_evidence!(context, sequence, completeness) do
    content =
      if completeness == :incomplete do
        "The note says what changed and what people need to do. It does not say what could go wrong."
      else
        "The note says what changed, what could go wrong, and what people need to do."
      end

    Store.create!(Model.Evidence, %{
      task_id: context.task.id,
      mutation_id: context.mutation.id,
      kind: "Check the three parts",
      content: content,
      source: "Note writer receipt #{context.mutation.receipt}",
      independently_checkable: true
    })

    summary =
      if completeness == :incomplete,
        do: "The work cell gives the note to the checker. One part is missing.",
        else: "The work cell gives the finished note to the checker."

    event!(context.system, context.task, sequence, "evidence_recorded", summary)
  end

  defp verify_pass!(context, sequence, notes) do
    confidence = if sequence > 10, do: Decimal.new("0.97"), else: Decimal.new("0.98")

    Store.create!(Model.Evaluation, %{
      task_id: context.task.id,
      evidence_id: context.evidence.id,
      verification_status: "passed",
      verdict: "meets_task",
      confidence: confidence,
      notes: notes
    })

    event!(
      context.system,
      context.task,
      sequence,
      "verified",
      "The checker finds all three parts."
    )
  end

  defp verify_fail!(context, sequence) do
    Store.create!(Model.Evaluation, %{
      task_id: context.task.id,
      evidence_id: context.evidence.id,
      verification_status: "failed",
      verdict: "rework_needed",
      confidence: Decimal.new("0.99"),
      notes: "The note does not say what could go wrong"
    })

    event!(
      context.system,
      context.task,
      sequence,
      "verification_failed",
      "The checker finds a missing part: what could go wrong."
    )
  end

  defp request_revision!(context, sequence) do
    event!(
      context.system,
      context.task,
      sequence,
      "rework_requested",
      "Mike asks the work cell to add the missing part.",
      %{"choice" => "request_revision"}
    )
  end

  defp rework_judgment!(context, sequence) do
    judgment!(
      context,
      context.methods["hybrid"],
      "Plan the fix",
      ["fix the note", "ask Mike for help"],
      "Fix the note because the rules allow it"
    )

    event!(
      context.system,
      context.task,
      sequence,
      "rework_judgment",
      "The work cell plans a small fix."
    )
  end

  defp revise_draft!(context, sequence) do
    mutation!(context, "revise", %{"phase" => "drafted", "revision" => 1}, %{
      "phase" => "revised",
      "revision" => 2,
      "path" => context.tool.allowed_path
    })

    event!(
      context.system,
      context.task,
      sequence,
      "mutation_applied",
      "The work cell adds the missing part."
    )
  end

  defp change_job!(context, sequence) do
    Store.update!(context.task, %{
      required_output:
        "One note with: what changed, what could go wrong, what people need to do, and where to get help",
      quantity: "One note with four parts"
    })

    event!(
      context.system,
      context.task,
      sequence,
      "job_changed",
      "Mike adds one new need: the note must say where people can get help."
    )
  end

  defp close_without_result!(context, sequence, task_status, kind, summary) do
    Store.update!(context.task, %{status: task_status})
    complete_work!(context)
    event!(context.system, context.task, sequence, kind, summary)
  end

  defp delegate_to_specialist!(context, sequence) do
    specialist =
      create_cell!(
        context.system,
        context.human,
        "Risk specialist cell",
        "risk-specialist",
        context.cell.id
      )

    Store.create!(Model.WorkExecution, %{
      task_id: context.task.id,
      work_cell_id: specialist.id,
      status: "in_progress",
      current_state: %{"phase" => "checking risks"}
    })

    event!(
      context.system,
      context.task,
      sequence,
      "specialist_started",
      "The writing work cell asks a smaller specialist cell to check the risks."
    )
  end

  defp specialist_returns!(context, sequence) do
    specialist_work = List.last(context.snapshot.work)
    Store.update!(specialist_work, %{status: "complete", current_state: %{"phase" => "returned"}})

    event!(
      context.system,
      context.task,
      sequence,
      "specialist_finished",
      "The specialist cell returns its risk check to the writing work cell."
    )
  end

  defp accept!(context, sequence, status, summary) do
    Store.create!(Model.Outcome, %{
      task_id: context.task.id,
      evaluation_id: context.evaluation.id,
      accepted_by_id: context.human.id,
      status: status,
      summary: summary,
      human_acceptance: "accepted"
    })

    Store.update!(context.task, %{status: "accepted"})
    complete_work!(context, %{"phase" => "accepted"})
    event!(context.system, context.task, sequence, "human_accepted", summary)
  end

  defp reject!(
         context,
         sequence,
         summary \\ "Mike stops the job because the note is missing a part."
       ) do
    Store.create!(Model.Outcome, %{
      task_id: context.task.id,
      evaluation_id: context.evaluation.id,
      accepted_by_id: context.human.id,
      status: "rejected",
      summary: summary,
      human_acceptance: "rejected"
    })

    Store.update!(context.task, %{status: "rejected"})
    complete_work!(context, %{"phase" => "rejected"})

    event!(context.system, context.task, sequence, "human_rejected", summary, %{
      "choice" => "end_run"
    })
  end

  defp complete_work!(context, state \\ %{"phase" => "closed"}) do
    Enum.each(
      context.snapshot.work,
      &Store.update!(&1, %{status: "complete", current_state: state})
    )
  end

  defp simple_event!(context, sequence, kind, summary) do
    event!(context.system, context.task, sequence, kind, summary)
  end

  defp judgment!(context, method, situation, options, decision_text) do
    judgment =
      Store.create!(Model.Judgment, %{
        actor_label: context.cell.name,
        work_cell_id: context.cell.id,
        task_id: context.task.id,
        method_id: method.id,
        situation: situation,
        observations: ["The job has clear rules", "The work cell has a safe work area"],
        options: options,
        decision_text: decision_text,
        stated_basis: "The job, its rules, and the saved story facts",
        uncertainty: "Low. This story always uses the same facts.",
        risk: "Mike still needs to say when the job is done."
      })

    Store.create!(Model.Decision, %{judgment_id: judgment.id, choice: decision_text})
  end

  defp mutation!(context, action, prior_state, resulting_state) do
    true = authorized?(context.authority, action)
    true = bounded_path?(context.workspace, resulting_state["path"])

    mutation =
      Store.create!(Model.Mutation, %{
        task_id: context.task.id,
        work_execution_id: context.work.id,
        authority_id: context.authority.id,
        prior_state: prior_state,
        action: action,
        resulting_state: resulting_state,
        authority_used: context.authority.name,
        receipt: receipt(action, resulting_state),
        authorized: true
      })

    Store.update!(context.work, %{current_state: resulting_state})
    mutation
  end

  defp create_cell!(system, human, name, id, parent_id \\ nil) do
    {:ok, _cell_spec} = Jido.Vsm.Topology.CellSpec.new(id: id)

    Store.create!(Model.WorkCell, %{
      work_system_id: system.id,
      accountable_actor_id: human.id,
      parent_id: parent_id,
      name: name,
      purpose: "Do one clear job and follow its rules",
      vsm_cell_id: id
    })
  end

  defp event!(system, task, sequence, kind, summary, data \\ %{}) do
    Store.create!(Model.Event, %{
      work_system_id: system.id,
      task_id: task && task.id,
      sequence: sequence,
      kind: kind,
      summary: summary,
      data: data
    })
  end

  defp authorized?(authority, action), do: action in authority.permitted_actions

  defp bounded_path?(workspace, path) do
    root = Path.expand(workspace.root)
    candidate = Path.expand(path, root)
    candidate == root or String.starts_with?(candidate, root <> "/")
  end

  defp receipt(action, state) do
    :crypto.hash(:sha256, :erlang.term_to_binary({action, state}))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp method_name("llm"), do: "Note writer"
  defp method_name("htn"), do: "Plan maker"
  defp method_name("decision_rule"), do: "Rule check"
  defp method_name(type), do: type |> String.replace("_", " ") |> String.capitalize()

  defp provider("llm"), do: "fixed local result"
  defp provider("htn"), do: "fixed task decomposition"
  defp provider("decision_rule"), do: "pure action membership rule"
  defp provider(type), do: "registered deterministic #{type} provider"

  defp first!([value | _]), do: value
end
