path =
  case System.argv() do
    ["rework"] -> :rework
    _ -> :success
  end

snapshot = JidoWorkSystem.Simulation.run(path)
task = List.first(snapshot.tasks)
outcome = List.first(snapshot.outcomes)

IO.puts("Simulation path: #{path}")
IO.puts("Task status: #{task.status}")
IO.puts("Outcome: #{outcome.status}")
IO.puts("Events: #{length(snapshot.events)}")
