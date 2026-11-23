defmodule ConnectBot.VaultCLI do
  alias ConnectBot.{GitHubOAuth, VaultHost}

  def main(args) do
    case run(args) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, message(reason))
        System.stop(1)
    end
  end

  defp run(["init"]), do: VaultHost.setup()

  defp run(["bind", agent, repo]) do
    with true <- valid_agent?(agent) and valid_repo?(repo),
         :ok <- VaultHost.start_storage(),
         token when is_binary(token) <- IO.read(:stdio, :line),
         token when byte_size(token) > 0 <- String.trim(token),
         :ok <- VaultHost.bind(agent, repo, token) do
      IO.puts("Bound #{agent} to #{repo}.")
    else
      false -> {:error, :usage}
      {:error, _} = error -> error
      _ -> {:error, :missing_token}
    end
  end

  defp run(["read", agent]) do
    with true <- valid_agent?(agent),
         :ok <- VaultHost.start_storage(),
         {:ok, issues} <- VaultHost.read(agent) do
      IO.puts(issues)
    else
      false -> {:error, :usage}
      {:error, _} = error -> error
    end
  end

  defp run(["connect", agent, repo]) do
    with true <- valid_agent?(agent) and valid_repo?(repo),
         :ok <- VaultHost.start_storage(),
         {:ok, credential} <- GitHubOAuth.device_authorize(&show_device_instructions/2),
         :ok <- VaultHost.bind(agent, repo, credential) do
      IO.puts("Bound #{agent} to #{repo}.")
    else
      false -> {:error, :usage}
      {:error, _} = error -> error
    end
  end

  defp run(["member", mode]) when mode in ["enable", "disable"] do
    with :ok <- VaultHost.start_storage(), do: VaultHost.set_membership(mode == "enable")
  end

  defp run(["delegate", agent]) do
    with true <- valid_agent?(agent),
         :ok <- VaultHost.start_storage(),
         {:ok, grant_id} <- VaultHost.delegate(agent) do
      IO.puts(grant_id)
    else
      false -> {:error, :usage}
      {:error, _} = error -> error
    end
  end

  defp run([command, id]) when command in ["enqueue", "execute", "revoke"] do
    with {:ok, id} <- Ash.Type.cast_input(:uuid, id),
         :ok <- VaultHost.start_storage() do
      case command do
        "enqueue" -> print_result(VaultHost.enqueue(id))
        "execute" -> print_result(VaultHost.execute(id))
        "revoke" -> VaultHost.revoke(id)
      end
    else
      :error -> {:error, :usage}
      {:error, _} = error -> error
    end
  end

  defp run(["--help"]) do
    IO.puts("""
    Usage:
      connect-bot vault init
      connect-bot vault bind AGENT OWNER/REPO   # read a GitHub token from stdin
      connect-bot vault connect AGENT OWNER/REPO
      connect-bot vault read AGENT
      connect-bot vault member enable|disable
      connect-bot vault delegate AGENT         # print a grant ID
      connect-bot vault enqueue GRANT_ID       # print a run ID
      connect-bot vault execute RUN_ID
      connect-bot vault revoke GRANT_ID
    """)
  end

  defp run(_), do: {:error, :usage}

  defp print_result({:ok, value}), do: IO.puts(value)
  defp print_result({:error, _} = error), do: error

  defp show_device_instructions(uri, code), do: IO.puts("Open #{uri} and enter #{code}.")

  defp valid_agent?(agent), do: Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, agent)

  defp valid_repo?(repo),
    do: Regex.match?(~r/\A[a-zA-Z0-9-]+\/(?!\.\.?\z)[a-zA-Z0-9_.-]+\z/, repo)

  defp message(:usage), do: "Use connect-bot vault --help."

  defp message(:storage_unavailable),
    do: "Could not open the vault. Run connect-bot vault init first."

  defp message(:missing_token), do: "Supply a GitHub token on standard input."
  defp message(:binding_unavailable), do: "No vault binding for that agent."
  defp message(:delegation_denied), do: "There is no active grant for this operation."
  defp message(:run_unavailable), do: "There is no queued run with that ID."

  defp message(:issue_read_failed),
    do: "The agent could not read issues. Check the GitHub token and repository."

  defp message(_), do: "The vault operation failed."
end
