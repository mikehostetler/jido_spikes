defmodule Section9.Cycle do
  @moduledoc "Shared observe, ReAct, validate, commit, and publish pulse engine."

  alias Section9.{Fixture, Ledger, Prompt, Proposal}

  def run(role, opts \\ []) do
    context = Ledger.context(role)
    prompt = Prompt.render(role, context)
    pulse_id = pulse_id(role, context)
    on_stream = stream_callback(role, pulse_id)
    adapter = Keyword.get(opts, :model_adapter, Application.fetch_env!(:section9, :model_adapter))

    Phoenix.PubSub.broadcast(
      Section9.PubSub,
      "section9:stream",
      {:pulse_started, role, pulse_id, prompt.exact}
    )

    with {:ok, raw} <-
           adapter.propose(
             role,
             %{context: context, prompt: prompt},
             Keyword.put(opts, :on_stream, on_stream)
           ),
         {:ok, proposal} <- Proposal.validate(role, raw) do
      evidence = evaluation_evidence(role, proposal, context)

      if Keyword.get(opts, :crash_after_candidate, false) and role == :implementer and
           proposal["action"]["type"] == "submit_candidate" do
        {:ok, _candidate_id} =
          Ledger.save_uncertain_candidate(
            pulse_id,
            proposal["action"]["source"],
            context.task.claim_generation
          )

        exit(:injected_after_candidate_save)
      end

      result =
        Ledger.commit_pulse(
          role,
          pulse_id,
          %{exact: prompt.exact, model: model_name(adapter, opts)},
          context.actor.state,
          proposal,
          context.task.claim_generation,
          evidence
        )

      if match?({:ok, _}, result) and role == :implementer and
           proposal["action"]["type"] == "submit_candidate" do
        Fixture.materialize(proposal["action"]["source"])
      end

      result
    end
  end

  defp evaluation_evidence(:evaluator, %{"action" => %{"type" => type}}, context)
       when type in ["evaluate_candidate", "request_rework"] do
    Section9.Fixture.run_acceptance(context.candidate.source)
  end

  defp evaluation_evidence(_role, _proposal, _context), do: nil

  defp stream_callback(role, pulse_id) do
    fn text ->
      Phoenix.PubSub.broadcast(
        Section9.PubSub,
        "section9:stream",
        {:pulse_stream, role, pulse_id, text}
      )
    end
  end

  defp pulse_id(role, context) do
    "#{context.mission.id}:#{role}:#{context.mission.pulses_used + 1}:#{System.unique_integer([:positive])}"
  end

  defp model_name(Section9.Model.Fake, _opts), do: "deterministic-fake"

  defp model_name(_adapter, opts),
    do: Keyword.get(opts, :model, Application.fetch_env!(:section9, :model))
end
