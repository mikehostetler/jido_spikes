defmodule Kura.Playbooks.Fixtures do
  @moduledoc false

  alias Kura.Maintenance
  alias Kura.Playbooks.{Runner, Triage}

  @dir Path.expand("../../../priv/maintenance", __DIR__)
  @snapshots_path Path.join(@dir, "ci_snapshots.json")
  @sparse_path Path.join(@dir, "sparse_failure.json")
  @review_path Path.join(@dir, "review_finding.txt")
  @external_resource @snapshots_path
  @external_resource @sparse_path
  @external_resource @review_path
  @snapshots @snapshots_path |> File.read!() |> JSON.decode!() |> Map.new(&{&1["id"], &1})
  @sparse @sparse_path |> File.read!() |> JSON.decode!()
  @review @review_path |> File.read!() |> String.trim()

  def snapshot(id), do: @snapshots[id]
  def sparse, do: @sparse
  def review_finding, do: @review

  def snapshot(id, scope), do: scoped(snapshot(id), scope)
  def sparse(scope), do: scoped(sparse(), scope)

  defp scoped(nil, _scope), do: nil
  defp scoped(snapshot, nil), do: snapshot

  defp scoped(snapshot, scope) do
    for key <- ["head", "check_head"], into: snapshot do
      digest = :crypto.hash(:sha, [scope, ":", snapshot[key]])
      {key, Base.encode16(digest, case: :lower)}
    end
  end

  def compare(baseline, candidate) when not is_nil(baseline) do
    with {:ok, baseline_cases} <- run_cases(baseline),
         {:ok, candidate_cases} <- run_cases(candidate) do
      passed =
        valid_ci_gate?() and
          baseline_cases["detailed"]["finding"] == candidate_cases["detailed"]["finding"] and
          candidate_cases["detailed"]["review_wait"] == false and
          candidate_cases["sparse"]["review_wait"] == true and
          candidate_cases["sparse"]["finding"] == @review

      result = %{
        "passed" => passed,
        "baseline" => baseline_cases,
        "candidate" => candidate_cases,
        "exact_commit_gate" => valid_ci_gate?()
      }

      {:ok, result}
    end
  end

  def compare(nil, _candidate), do: {:error, :missing_ci_baseline}

  defp run_cases(version) do
    with {:ok, detailed} <-
           Runner.replay(version, snapshot("failure"), %{
             "finding" => snapshot("failure")["evidence"]
           }),
         {:ok, sparse} <- Runner.replay(version, sparse(), %{"finding" => @review}),
         true <- detailed.status == :succeeded and sparse.status == :succeeded do
      {:ok, %{"detailed" => Triage.result(detailed), "sparse" => Triage.result(sparse)}}
    else
      false -> {:error, :fixture_run_failed}
      error -> error
    end
  end

  defp valid_ci_gate? do
    original = snapshot("failure")["head"]
    head = snapshot("new_head")["head"]

    match?({"waiting_ci", _}, Maintenance.ci_gate(snapshot("stale_pass"), head, original)) and
      match?({"closed", _}, Maintenance.ci_gate(snapshot("pass"), head, original))
  end
end
