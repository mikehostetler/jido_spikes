defmodule Kura.Playbooks.Triage do
  @moduledoc false

  alias Jido.HTN.{CompoundTask, Domain, Method, PrimitiveTask}

  defmodule AskReview do
    use Jido.Action,
      name: "kura_ask_review_for_assertion",
      schema: Jido.Joi.map()

    def run(_facts, _context) do
      {:ok, %{"review_question" => "What did the failing assertion expect and receive?"}}
    end
  end

  defmodule RecordFinding do
    use Jido.Action,
      name: "kura_record_ci_finding",
      schema: Jido.Joi.map()

    def run(facts, _context) do
      finding = get_in(facts, ["review", "finding"]) || facts["evidence"]
      {:ok, %{"triage_finding" => finding}}
    end
  end

  def missing_assertion?(facts), do: facts["assertion_complete"] != true

  def registration do
    %{
      name: "Triage failed CI",
      trigger: "ci_snapshot",
      valid_input?: &valid_input?/1,
      wait: &wait/1,
      revise: &revise/2,
      replay: &Kura.Playbooks.Fixtures.compare/2,
      capability: "ci_triage",
      root: "triage",
      targets: %{
        {"kura/ask-review", 1} => AskReview,
        {"kura/record-finding", 1} => RecordFinding,
        {"kura/missing-assertion", 1} => &__MODULE__.missing_assertion?/1
      }
    }
  end

  defp valid_input?(%{
         "id" => "failure",
         "status" => "failed",
         "head" => head,
         "check_head" => head,
         "evidence" => evidence,
         "assertion_complete" => complete
       })
       when is_binary(head) and is_binary(evidence) and is_boolean(complete),
       do: byte_size(head) == 40 and evidence != ""

  defp valid_input?(_), do: false

  defp wait(%{"review_question" => question}) when is_binary(question) do
    %{kind: :external_signal, prompt: question, payload: %{"state_key" => "review"}}
  end

  defp wait(_), do: nil

  def result(run) do
    result = Kura.Playbooks.Runner.result(run, "triage_finding")
    Map.put(result, "review_wait", result["waited"])
  end

  def seed, do: Kura.Playbooks.seed("cedar", "ci_triage", baseline())

  defp baseline do
    Domain.new_domain!(%{
      name: "CI triage",
      root_tasks: ["triage"],
      allowed_workflows: %{"ask_review" => AskReview, "record_finding" => RecordFinding},
      callbacks: %{"missing_assertion" => &__MODULE__.missing_assertion?/1},
      tasks: %{
        "triage" =>
          CompoundTask.new("triage", [
            Method.new!(
              name: "ask_review",
              priority: 0,
              subtasks: ["ask_review", "record_finding"]
            ),
            Method.new!(name: "use_ci_evidence", priority: 1, subtasks: ["record_finding"])
          ]),
        "ask_review" => PrimitiveTask.new!("ask_review", {AskReview, []}),
        "record_finding" => PrimitiveTask.new!("record_finding", {RecordFinding, []})
      }
    })
  end

  def revise(domain, %{"method" => "ask_review", "condition" => "missing_assertion"} = change)
      when map_size(change) == 2 do
    {:ok,
     update_in(domain.tasks["triage"].methods, fn methods ->
       Enum.map(methods, fn
         %{name: "ask_review"} = method -> %{method | conditions: ["missing_assertion"]}
         method -> method
       end)
     end)}
  end

  def revise(_domain, _change), do: {:error, :unsupported_method_edit}
end
