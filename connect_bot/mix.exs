defmodule ConnectBot.MixProject do
  use Mix.Project

  def project do
    connect = System.get_env("CONNECT_BOT_CONNECT_PATH") || "../../jido_connect/jido_connect"

    vault? = Mix.env() == :cli

    [
      app: :connect_bot,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps_path: if(vault?, do: "deps", else: Path.join(connect, "deps")),
      lockfile: if(vault?, do: "cli.mix.lock", else: Path.join(connect, "mix.lock")),
      test_paths: if(vault?, do: ["cli/test"], else: ["test"]),
      elixirc_paths: if(vault?, do: ["lib/connect_bot", "cli"], else: ["lib"]),
      deps:
        [
          {:jido_connect, path: Path.join(connect, "apps/jido_connect")},
          {:jido_connect_github, path: Path.join(connect, "apps/jido_connect_github")}
        ] ++ profile_deps(vault?)
    ]
  end

  defp profile_deps(true), do: [{:ash_vault, "~> 0.1.0"}, {:simple_sat, "~> 0.1"}]

  defp profile_deps(false) do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.3"},
      {:bandit, "~> 1.12"}
    ]
  end

  def application do
    extras = if Mix.env() == :cli, do: [:logger, :mnesia], else: [:logger]
    [mod: {ConnectBot.Application, []}, extra_applications: extras]
  end
end
