defmodule Section9.Model do
  @moduledoc "Model adapter contract for one Section 9 pulse."

  @callback propose(atom(), map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Section9.Model.Fake do
  @moduledoc "Deterministic model for ledger, permission, and recovery tests."
  @behaviour Section9.Model

  @impl true
  def propose(role, %{context: context}, opts) do
    stream(opts, "Inspecting committed #{role} facts. ")
    stream(opts, "Preparing one permitted action.")

    audit = %{
      "skill_mode" => "host-validated deterministic adapter",
      "loaded_skills" => context.actor.skills
    }

    {:ok, Map.put(proposal(role, context), "audit", audit)}
  end

  defp proposal(:lead, %{task: %{status: status}}) when status in ["pending", "rework"] do
    %{
      "narrative" => "The lead assigned the current repair claim to the implementer.",
      "next_state" => %{
        "focus" => "Wait for a candidate from the current claim.",
        "facts" => ["The task has a current implementer claim."],
        "next_step" => "Inspect candidate evidence."
      },
      "action" => %{"type" => "assign_implementer"}
    }
  end

  defp proposal(:lead, %{task: %{status: "passed"}, evaluation: evaluation}) do
    %{
      "narrative" => "The lead closed the mission because the current evaluation passed.",
      "next_state" => %{
        "focus" => "Mission closed.",
        "facts" => ["Evaluation #{evaluation.id} passed."],
        "next_step" => "Retain the ledger evidence."
      },
      "action" => %{"type" => "close_mission"}
    }
  end

  defp proposal(:implementer, %{task: %{status: "claimed"}}) do
    %{
      "narrative" => "The implementer removed ownership on cancel and consumed each result once.",
      "next_state" => %{
        "focus" => "Candidate submitted for independent evaluation.",
        "facts" => ["Cancellation and result handlers use Map.pop."],
        "next_step" => "Wait for evaluator evidence."
      },
      "action" => %{"type" => "submit_candidate", "source" => Section9.Fixture.repaired_source()}
    }
  end

  defp proposal(:evaluator, %{task: %{status: "candidate_ready"}}) do
    %{
      "narrative" =>
        "The evaluator requested the protected acceptance run without changing the candidate.",
      "next_state" => %{
        "focus" => "Record independent command evidence.",
        "facts" => ["The evaluator has no candidate write permission."],
        "next_step" => "Return pass or rework from the command result."
      },
      "action" => %{"type" => "evaluate_candidate"}
    }
  end

  defp proposal(role, _context) do
    %{
      "narrative" => "No legal work action is ready for #{role}.",
      "next_state" => %{
        "focus" => "Wait for a legal task transition.",
        "facts" => ["No permitted transition is ready."],
        "next_step" => "Reload the ledger on the next pulse."
      },
      "action" => %{"type" => "wait"}
    }
  end

  defp stream(opts, text) do
    if callback = opts[:on_stream], do: callback.(text)
  end
end
