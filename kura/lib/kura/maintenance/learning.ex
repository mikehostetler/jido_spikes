defmodule Kura.Maintenance.Learning do
  @moduledoc false

  alias Jido.HTN
  alias Kura.Cell.Inbox
  alias Kura.{Maintenance, Playbooks}
  alias Kura.Playbooks.{Fixtures, Triage}

  @change %{"method" => "ask_review", "condition" => "missing_assertion"}

  def run(%{id: case_id, state: state} = record) do
    trace =
      with {:ok, observations, facts} <- observations(record),
           {:ok, version} <- Playbooks.get("cedar", state["triage_version"]),
           {:ok, baseline} <- Playbooks.decode(version),
           {:ok, candidate} <- Triage.revise(baseline, @change),
           {:ok, result} <- search(baseline, candidate, facts) do
        %{
          "case_id" => case_id,
          "observations" => observations,
          "scores" => Map.new(result.history, &score_entry/1),
          "change" =>
            if(result.value.guard_review and result.best.evaluation.selected_score == 1.0,
              do: @change
            )
        }
      else
        {:error, reason} -> %{"reason" => format_reason(reason)}
      end

    output =
      if trace["change"],
        do: "Tune selected a guard for the Review method.",
        else: "Tune found no change to save."

    {{:ok, output},
     %{"status" => "local_demo", "output" => output, "tools" => [], "learning" => trace}}
  end

  defp observations(%{id: case_id, state: state} = record) do
    entries = Inbox.scoped_events(Maintenance.worker_id(record), case_id)

    with %{"run_id" => run_id, "wait_id" => wait_id} <- state["playbook"],
         %{
           id: ^run_id,
           payload: %{"assertion_complete" => true, "evidence" => finding, "head" => head} = facts
         } = ci <- Enum.find(entries, &(&1.id == run_id)),
         true <- completed?(ci, "ci_snapshot"),
         %{
           payload: %{
             "finding" => ^finding,
             "head" => ^head,
             "run_id" => ^run_id,
             "wait_id" => ^wait_id
           }
         } =
           reply <- Enum.find(entries, &completed?(&1, "review_reply")),
         true <- is_binary(finding) and finding != "" do
      {:ok, %{"ci_pulse_id" => run_id, "review_pulse_id" => reply.id}, facts}
    else
      _ -> {:error, :no_redundant_review_in_saved_traces}
    end
  end

  defp completed?(%{kind: kind, status: "completed", trace: %{"status" => status}}, kind),
    do: status in ["completed", "local_demo"]

  defp completed?(_entry, _kind), do: false

  defp search(baseline, candidate, facts) do
    domains = %{false => baseline, true => candidate}

    Tune.new(%{guard_review: false},
      run: fn %{guard_review: guard}, facts ->
        HTN.plan(Map.fetch!(domains, guard), facts, strict: true) |> plan_actions()
      end
    )
    |> Tune.data(
      validation: [
        %{id: "saved_ci", input: facts, expected: [Triage.RecordFinding]},
        %{
          id: "sparse_fixture",
          input: Fixtures.sparse(),
          expected: [Triage.AskReview, Triage.RecordFinding]
        }
      ]
    )
    |> Tune.vary(guard_review: [false, true])
    |> Tune.score(:expected_actions, fn row, actions ->
      if actions == row.expected, do: 1.0, else: 0.0
    end)
    |> Tune.search(:grid)
    |> Tune.limit(evaluations: 2)
    |> Tune.tune()
  end

  defp plan_actions({:ok, plan, _}), do: Enum.map(plan, &elem(&1, 0))
  defp plan_actions({:error, _}), do: []

  defp score_entry(candidate) do
    label = if candidate.value.guard_review, do: "guarded", else: "baseline"
    {label, candidate.evaluation.selected_score}
  end

  defp format_reason(:no_redundant_review_in_saved_traces),
    do: "No saved CI and Review traces show a repeated finding."

  defp format_reason(%{__exception__: true} = error), do: Exception.message(error)
  defp format_reason(reason), do: inspect(reason)
end
