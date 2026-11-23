defmodule Kura.Playbooks.Observation do
  @moduledoc "Pine's task for recording a verified observation of its workspace."
  @behaviour Jido.Holon.Pulse

  alias Jido.{Catalog, Codec}
  alias Jido.HTN.{CompoundTask, Domain, Method, PrimitiveTask}
  alias Kura.Cell.{Control, Workspace}
  alias Kura.Playbooks
  alias Kura.Playbooks.Runner

  @task "record_observation"

  defmodule Record do
    use Jido.Action, name: "kura_record_workspace_observation", schema: Jido.Joi.map()

    def run(%{"evidence" => evidence}, _context), do: {:ok, %{"finding" => evidence}}
  end

  def registration do
    %{
      name: "Record observation",
      trigger: "workspace_observation",
      valid_input?: &valid_input?/1,
      replay: &compare/2,
      root: "observation",
      capability: "workspace_read",
      targets: %{{"kura/record-finding", 1} => Record}
    }
  end

  @impl true
  def run(cell, workspace, entry) do
    result =
      with {:ok, receipt} <- Control.authorize(cell, entry.id),
           {:ok, observation} <- Workspace.inspect_brief(workspace, cell.id) do
        outcome(cell.id, entry, observation)
        |> append_receipt(receipt)
      end

    {result, nil}
  end

  defp outcome(cell, entry, observation) do
    facts = %{"evidence" => "SHA-256 " <> observation["sha256"]}

    case Playbooks.active(cell, @task) do
      nil ->
        with {:ok, version} <- draft(cell, entry.id, facts) do
          {:ok, "Saved playbook draft #{version.revision} for replay."}
        end

      version ->
        with {:ok, %{status: :succeeded} = run} <-
               Runner.start(version, entry.kind, facts, entry.id),
             %{"finding" => finding} when is_binary(finding) <- Runner.result(run) do
          {:ok, "Playbook v#{version.revision} recorded #{finding}."}
        else
          {:error, _} = error -> error
          _ -> {:error, :observation_playbook_incomplete}
        end
    end
  end

  defp draft(cell, id, facts) do
    catalog = Catalog.from_targets!(__MODULE__, :jido_htn, registration().targets)

    domain =
      Domain.new_domain!(%{
        name: "Record observation",
        root_tasks: ["observation"],
        allowed_workflows: %{"record" => Record},
        tasks: %{
          "observation" => CompoundTask.new("observation", [Method.new!(subtasks: ["record"])]),
          "record" => PrimitiveTask.new!("record", {Record, []})
        }
      })

    with {:ok, document} <- Codec.encode(domain, catalog: catalog) do
      Playbooks.propose_initial(cell, @task, id, facts, document)
    end
  end

  defp compare(nil, candidate) do
    evidence = "SHA-256 " <> String.duplicate("0", 64)

    with {:ok, run} <- Runner.replay(candidate, %{"evidence" => evidence}, %{}) do
      observed = Runner.result(run)
      passed = run.status == :succeeded and observed["finding"] == evidence
      {:ok, %{"passed" => passed, "expected" => evidence, "observed" => observed}}
    end
  end

  defp compare(_baseline, _candidate), do: {:error, :unsupported_observation_edit}

  defp valid_input?(%{"evidence" => "SHA-256 " <> digest}),
    do: byte_size(digest) == 64 and Regex.match?(~r/\A[0-9a-f]+\z/, digest)

  defp valid_input?(_), do: false

  defp append_receipt({:ok, output}, receipt), do: {:ok, output <> "\nControl: " <> receipt}
  defp append_receipt(error, _receipt), do: error
end
