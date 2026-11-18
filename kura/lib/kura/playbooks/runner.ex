defmodule Kura.Playbooks.Runner do
  @moduledoc "Steps a pinned Loom playbook to its next wait or outcome."

  alias Jido.Loom
  alias Kura.Playbooks
  alias Kura.Playbooks.Storage

  def start(version, trigger, facts, id) do
    if Playbooks.eligible?(version, trigger, facts) do
      with {:ok, task} <- Playbooks.registration(version.cell_id, version.task),
           {:ok, run} <- load_or_start(version, facts, id, :work),
           do: advance(run, task, 8)
    else
      {:error, :playbook_ineligible}
    end
  end

  def replay(version, facts, reply) do
    with {:ok, task} <- Playbooks.registration(version.cell_id, version.task),
         true <- task.valid_input?.(facts),
         {:ok, run} <-
           load_or_start(
             version,
             Map.put(facts, "fixture_replay", true),
             Ash.UUID.generate(),
             :fixture
           ),
         {:ok, run} <- advance(run, task, 8) do
      case open_wait(run) do
        nil -> {:ok, run}
        wait -> resume(run, wait.id, reply, task)
      end
    else
      false -> {:error, :invalid_fixture_input}
      error -> error
    end
  end

  defp load_or_start(version, facts, id, mode) do
    case Storage.get_run(id) do
      {:ok, %{playbook_ref: %{playbook_id: version_id}} = run} when version_id == version.id ->
        {:ok, run}

      {:error, %{type: :not_found, message: "Loom record missing"}} ->
        start_run(version, facts, id, mode)

      _ ->
        {:error, :run_unavailable}
    end
  end

  defp start_run(version, facts, id, mode) do
    with {:ok, definition} <- Playbooks.definition(version, mode),
         do: Loom.start_run(definition, facts, id: id)
  end

  def resume(run, wait_id, reply) do
    with {:ok, task} <- Playbooks.run_registration(run.playbook_ref.playbook_id) do
      resume(run, wait_id, reply, task)
    end
  end

  defp resume(run, wait_id, reply, task) do
    case Enum.find(run.wait_points, &(&1.id == wait_id)) do
      %{status: :open} ->
        with {:ok, resumed} <-
               Loom.signal(run,
                 kind: :external_signal,
                 run_id: run.id,
                 wait_point_id: wait_id,
                 payload: reply
               ),
             do: advance(resumed, task, 8)

      %{status: :resolved} ->
        advance(run, task, 8)

      _ ->
        {:error, :unmatched_wait}
    end
  end

  def open_wait(run), do: Enum.find(run.wait_points, &(&1.status == :open))

  def result(run, finding_key \\ "finding") do
    %{
      "id" => run.id,
      "method" => run.method_selections |> List.first() |> method_name(),
      "status" => to_string(run.status),
      "waited" => run.wait_points != [],
      "finding" => run.projected_state.data[finding_key]
    }
  end

  defp method_name(nil), do: nil
  defp method_name(selection), do: selection.method_name

  defp advance(%{status: status} = run, _task, _remaining)
       when status in [:waiting, :succeeded],
       do: {:ok, run}

  defp advance(%{status: status}, _task, _remaining) when status in [:failed, :cancelled],
    do: {:error, {:playbook_stopped, status}}

  defp advance(_run, _task, 0), do: {:error, :playbook_step_limit}

  defp advance(run, task, remaining) do
    wait =
      case {task[:wait], run.wait_points} do
        {wait, []} when is_function(wait, 1) -> wait.(run.projected_state.data)
        _ -> nil
      end

    if wait do
      Loom.open_wait(run, wait)
    else
      with {:ok, next} <- Loom.step(run), do: advance(next, task, remaining - 1)
    end
  end
end
