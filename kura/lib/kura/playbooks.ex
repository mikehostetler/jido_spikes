defmodule Kura.Playbooks do
  @moduledoc "Versioned procedures and trusted Catalog binding for cell tasks."

  import Ecto.Query, only: [from: 2]
  alias Jido.{Catalog, Codec, Loom}
  alias Jido.HTN.{Domain, Playbook}
  alias Kura.Cell.Catalog, as: Cells
  alias Kura.Repo

  defmodule Version do
    use Ecto.Schema

    @primary_key {:id, :string, autogenerate: false}
    schema "playbook_versions" do
      field :cell_id, :string
      field :task, :string
      field :revision, :integer
      field :document, :map
      field :base_id, :string
      field :evidence, :map
      field :replay, :map
      field :approved, :boolean, default: false
      field :active, :boolean, default: false
    end
  end

  def registration(cell, task) do
    with {:ok, profile} <- Cells.fetch(cell),
         {:ok, registration} <- Map.fetch(profile.playbook_tasks, task),
         true <- registration.capability in profile.capabilities do
      {:ok, registration}
    else
      _ -> {:error, :unavailable_cell_task}
    end
  end

  def run_registration(version_id) do
    case Repo.get(Version, version_id) do
      %Version{} = version -> registration(version.cell_id, version.task)
      nil -> {:error, :unknown_version}
    end
  end

  def get(cell, id) do
    case Repo.get_by(Version, cell_id: cell, id: id) do
      nil -> {:error, :unknown_version}
      version -> {:ok, version}
    end
  end

  def versions(cell, task) do
    Repo.all(
      from v in Version,
        where: v.cell_id == ^cell and v.task == ^task,
        order_by: [desc: v.revision, asc: v.id]
    )
  end

  def active(cell, task) do
    Repo.get_by(Version, cell_id: cell, task: task, active: true)
  end

  def eligible?(%Version{approved: true} = version, trigger, facts) do
    with {:ok, task} <- registration(version.cell_id, version.task) do
      task.trigger == trigger and task.valid_input?.(facts)
    else
      _ -> false
    end
  end

  def eligible?(_, _, _), do: false

  def seed(cell, task, domain) do
    ensure(
      %Version{
        id: "#{cell}:#{task}:v1",
        cell_id: cell,
        task: task,
        revision: 1,
        approved: true,
        active: true,
        evidence: %{"source" => "seed"}
      },
      domain
    )
  end

  def proposal(base, pulse_id, evidence, change) do
    with {:ok, %{revise: revise}} <- registration(base.cell_id, base.task),
         {:ok, domain} <- decode(base),
         {:ok, candidate} <- revise.(domain, change) do
      ensure(
        %Version{
          id: pulse_id,
          cell_id: base.cell_id,
          task: base.task,
          base_id: base.id,
          revision: base.revision + 1,
          evidence: Map.put(evidence, "change", change)
        },
        candidate
      )
    else
      {:ok, _} -> {:error, :unsupported_method_edit}
      error -> error
    end
  end

  def propose_initial(cell, task, pulse_id, evidence, document) do
    version = %Version{
      id: pulse_id,
      cell_id: cell,
      task: task,
      revision: 1,
      evidence: evidence,
      document: document
    }

    with nil <- active(cell, task),
         {:ok, domain} <- decode(version) do
      ensure(version, domain)
    else
      %Version{} -> {:error, :active_version_exists}
      error -> error
    end
  end

  defp ensure(version, domain) do
    with {:ok, task} <- registration(version.cell_id, version.task),
         true <- MapSet.equal?(domain.root_tasks, MapSet.new([task.root])),
         {:ok, document} <- Codec.encode(domain, catalog: catalog(task)),
         {:ok, _} <-
           Repo.insert(%{version | document: document},
             on_conflict: :nothing,
             conflict_target: [:id]
           ) do
      get(version.cell_id, version.id)
    else
      false -> {:error, :wrong_root_task}
      error -> error
    end
  end

  def decode(%Version{} = version) do
    with {:ok, task} <- registration(version.cell_id, version.task),
         {:ok, domain} <-
           Codec.decode(version.document, codec: Domain.Codec, catalog: catalog(task)),
         true <- MapSet.equal?(domain.root_tasks, MapSet.new([task.root])) do
      {:ok, domain}
    else
      false -> {:error, :wrong_root_task}
      error -> error
    end
  end

  def definition(%Version{} = version, mode \\ :work) do
    with :ok <- execution_permission(version, mode),
         {:ok, task} <- registration(version.cell_id, version.task),
         {:ok, domain} <- decode(version),
         {:ok, playbook} <-
           Playbook.new(%{
             schema_version: 1,
             id: version.id,
             name: task.name,
             version: Integer.to_string(version.revision),
             status: if(version.approved, do: "approved", else: "draft"),
             default_entrypoint: version.task,
             entrypoints: [
               %{id: version.task, name: task.name, summary: task.name, root_tasks: [task.root]}
             ],
             domain: domain
           }) do
      if mode == :work,
        do: Loom.Playbooks.compile_executable(playbook),
        else: Loom.compile(playbook)
    end
  end

  defp execution_permission(%Version{approved: true}, _mode), do: :ok
  defp execution_permission(_version, :fixture), do: :ok
  defp execution_permission(_version, _mode), do: {:error, :unapproved_playbook}

  def replay(cell, id) do
    with {:ok, candidate} <- get(cell, id),
         {:ok, task} <- registration(cell, candidate.task),
         {:ok, baseline} <- baseline(candidate),
         {:ok, result} <- task.replay.(baseline, candidate) do
      update(candidate, replay: result)
    end
  end

  defp baseline(%Version{base_id: nil}), do: {:ok, nil}
  defp baseline(%Version{cell_id: cell, base_id: id}), do: get(cell, id)

  def approve(cell, id) do
    Repo.transact(fn ->
      with {:ok, version} <- get(cell, id),
           true <- version.replay && version.replay["passed"],
           {:ok, _} <- decode(version),
           current = active(cell, version.task),
           true <- version.base_id == (current && current.id),
           {:ok, _} <- deactivate(current) do
        update(version, approved: true, active: true)
      else
        {:error, _} = error -> error
        _ -> {:error, :candidate_not_eligible}
      end
    end)
  end

  defp deactivate(nil), do: {:ok, nil}
  defp deactivate(version), do: update(version, active: false)

  defp update(version, attrs), do: version |> Ecto.Changeset.change(attrs) |> Repo.update()

  defp catalog(task), do: Catalog.from_targets!(__MODULE__, :jido_htn, task.targets)
end
