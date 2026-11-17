defmodule Section9.MixProject do
  use Mix.Project

  def project do
    [
      app: :section9,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Section9.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido,
       github: "agentjido/jido", ref: "ec96da6015b4b1e5a1642d50651235d9d52808ec", override: true},
      {:jido_vsm,
       git: Path.expand("../../jido_workflow/jido_vsm", __DIR__),
       ref: "fa7f0d820b59ca01e4867d63e6f0f8b044ae1313"},
      {:exqlite, "~> 0.43"},
      {:phoenix, "~> 1.8.16"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_html, "~> 4.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
