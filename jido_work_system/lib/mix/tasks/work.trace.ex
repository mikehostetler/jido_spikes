defmodule Mix.Tasks.Work.Trace do
  use Mix.Task

  @shortdoc "Run one headless work story and print its trace"

  @switches [scenario: :string, choice: :string, output: :string, max_steps: :integer]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    if rest != [] or invalid != [] do
      Mix.raise("Use --scenario, --choice, --max-steps, and --output only.")
    end

    scenario = Keyword.get(opts, :scenario, "straight-through-release")
    choice = Keyword.get(opts, :choice, "request_revision")
    max_steps = Keyword.get(opts, :max_steps, 100)

    case JidoWorkSystem.Headless.run(scenario, choice: choice, max_steps: max_steps) do
      {:ok, trace} -> write_json(trace, opts[:output])
      {:error, reason} -> Mix.raise("Headless story failed: #{inspect(reason)}")
    end
  end

  defp write_json(value, nil), do: IO.puts(Jason.encode!(value, pretty: true))

  defp write_json(value, path) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Jason.encode!(value, pretty: true) <> "\n")
    Mix.shell().info("Wrote trace to #{path}")
  end
end
