defmodule Mix.Tasks.Work.Pressure do
  use Mix.Task

  @shortdoc "Run many headless work stories and check every trace"

  @switches [runs: :integer, output: :string, trace_dir: :string]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    if rest != [] or invalid != [] do
      Mix.raise("Use --runs, --output, and --trace-dir only.")
    end

    case JidoWorkSystem.Headless.pressure(runs: Keyword.get(opts, :runs, 100)) do
      {:ok, report} ->
        maybe_write_traces(report.traces, opts[:trace_dir])
        summary = Map.delete(report, :traces)
        write_summary(summary, opts[:output])

        unless report.valid do
          Mix.raise("Pressure run found #{report.violation_count} rule problems.")
        end

      {:error, reason} ->
        Mix.raise("Pressure run failed: #{inspect(reason)}")
    end
  end

  defp maybe_write_traces(_traces, nil), do: :ok

  defp maybe_write_traces(traces, directory) do
    File.mkdir_p!(directory)

    Enum.with_index(traces, 1)
    |> Enum.each(fn {trace, index} ->
      name = "#{String.pad_leading(Integer.to_string(index), 4, "0")}-#{trace.scenario}.json"
      File.write!(Path.join(directory, name), Jason.encode!(trace, pretty: true) <> "\n")
    end)

    Mix.shell().info("Wrote #{length(traces)} traces to #{directory}")
  end

  defp write_summary(summary, nil), do: IO.puts(Jason.encode!(summary, pretty: true))

  defp write_summary(summary, path) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Jason.encode!(summary, pretty: true) <> "\n")
    Mix.shell().info("Wrote pressure summary to #{path}")
  end
end
