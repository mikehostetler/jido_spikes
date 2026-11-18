defmodule Kura.Cell.Bindings do
  @moduledoc "Resolves the approved handlers and tasks available to data-defined cells."

  @handlers %{
    "workspace.inspect@1" => {Kura.WorkspaceInspection, ["workspace_read", "digest"]},
    "workspace.observe@1" => {Kura.Playbooks.Observation, ["workspace_read"]}
  }
  @tasks %{"workspace.record_observation@1" => Kura.Playbooks.Observation}

  def resolve(%{"runtime" => runtime} = profile) do
    capabilities = profile["capabilities"]

    with {:ok, handlers} <- bind(runtime["handlers"], &resolve_handler(&1, capabilities)),
         {:ok, tasks} <- bind(runtime["tasks"], &resolve_task(&1, capabilities)),
         true <- Enum.all?(Map.values(profile["signals"]), &Map.has_key?(handlers, &1)),
         true <- Enum.all?(tasks, fn {_, task} -> Map.has_key?(handlers, task.trigger) end),
         true <- observation_binding?(handlers, tasks),
         true <- Enum.all?(profile["skills"], &(&1 == "jido")),
         true <- Enum.all?(capabilities, &(&1 in ["workspace_read", "digest"])),
         true <- valid_workspace?(runtime["workspace"]),
         true <- runtime["cognition"] in ["local", "inherit"] do
      {:ok, {handlers, tasks}}
    else
      _ -> {:error, :invalid_cell_bindings}
    end
  end

  defp bind(entries, resolve) when is_map(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {key, ref}, {:ok, acc} ->
      case is_binary(key) && key != "" && resolve.(ref) do
        {:ok, target} -> {:cont, {:ok, Map.put(acc, key, target)}}
        _ -> {:halt, {:error, :unknown_binding}}
      end
    end)
  end

  defp bind(_, _), do: {:error, :invalid_bindings}

  defp resolve_handler(ref, capabilities) do
    with {handler, required} <- @handlers[ref],
         true <- Enum.all?(required, &(&1 in capabilities)) do
      {:ok, handler}
    else
      _ -> :error
    end
  end

  defp resolve_task(ref, capabilities) do
    with {:ok, module} <- Map.fetch(@tasks, ref),
         task = module.registration(),
         true <- task.capability in capabilities do
      {:ok, task}
    else
      _ -> :error
    end
  end

  # This handler is also the task's live entry point.
  defp observation_binding?(handlers, tasks) do
    case {handlers["workspace_observation"], tasks["record_observation"]} do
      {nil, nil} -> Kura.Playbooks.Observation not in Map.values(handlers)
      {Kura.Playbooks.Observation, %{trigger: "workspace_observation"}} -> true
      _ -> false
    end
  end

  defp valid_workspace?(%{"policy" => "read_only"} = workspace) do
    Map.keys(workspace) -- ["policy", "brief"] == [] and
      (not Map.has_key?(workspace, "brief") or
         (is_binary(workspace["brief"]) and byte_size(workspace["brief"]) <= 65_536))
  end

  defp valid_workspace?(_), do: false
end
