defmodule Section9.Trace do
  @moduledoc "Captures bounded Jido and ReqLLM telemetry for one demo run."

  @metadata_keys [
    :request_id,
    :run_id,
    :session_id,
    :thread_id,
    :turn_id,
    :agent_id,
    :agent_name,
    :reasoning_name,
    :reasoning_method,
    :tool_name,
    :tool_call_id,
    :operation,
    :mode,
    :provider,
    :status,
    :finish_reason,
    :http_status,
    :reason_code,
    :error_type,
    :retryable?
  ]

  def capture(label, fun) when is_binary(label) and is_function(fun, 0) do
    parent = self()
    handler_id = "section9-trace-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        Jido.Telemetry.AI.events(),
        fn event, measurements, metadata, target ->
          send(target, {:section9_trace, trace_event(event, measurements, metadata)})
        end,
        parent
      )

    started_at = DateTime.utc_now()
    started_ms = System.monotonic_time(:millisecond)

    result =
      try do
        fun.()
      rescue
        error -> {:captured_exception, Exception.format(:error, error, __STACKTRACE__)}
      catch
        kind, reason -> {:captured_exit, kind, inspect(reason)}
      end

    elapsed_ms = System.monotonic_time(:millisecond) - started_ms
    :telemetry.detach(handler_id)
    telemetry = drain([])
    snapshot = Section9.Ledger.snapshot()

    trace = %{
      schema: "section9.trace/v1",
      label: label,
      model: Application.fetch_env!(:section9, :model),
      started_at: DateTime.to_iso8601(started_at),
      elapsed_ms: elapsed_ms,
      result: inspect(result, limit: 200, printable_limit: 8_000),
      telemetry: telemetry,
      ledger: ledger_summary(snapshot)
    }

    directory = Path.expand("../../traces", __DIR__)
    File.mkdir_p!(directory)
    stamp = Calendar.strftime(started_at, "%Y%m%dT%H%M%SZ")
    path = Path.join(directory, "#{stamp}-#{label}.json")
    File.write!(path, Jason.encode!(trace, pretty: true))
    {result, path, trace}
  end

  defp drain(events) do
    receive do
      {:section9_trace, event} -> drain([event | events])
    after
      0 -> Enum.reverse(events)
    end
  end

  defp trace_event(event, measurements, metadata) do
    %{
      event: Enum.join(event, "."),
      measurements: measurement_summary(measurements),
      metadata: metadata_summary(metadata)
    }
  end

  defp measurement_summary(measurements) do
    measurements
    |> Map.take([:duration, :system_time, :count, :model_calls, :tool_calls, :tool_rounds])
    |> Enum.map(fn
      {:duration, value} when is_integer(value) ->
        {"duration_ms", System.convert_time_unit(value, :native, :millisecond)}

      {key, value} ->
        {to_string(key), scalar(value)}
    end)
    |> Map.new()
  end

  defp metadata_summary(metadata) do
    base =
      metadata
      |> Map.take(@metadata_keys)
      |> Enum.map(fn {key, value} -> {to_string(key), scalar(value)} end)
      |> Map.new()

    base
    |> maybe_put("model", model_id(metadata[:model]))
    |> maybe_put("usage", usage(metadata[:usage]))
    |> maybe_put("error", error(metadata[:error]))
  end

  defp ledger_summary(snapshot) do
    %{
      mission: snapshot.mission,
      task: snapshot.task,
      candidate:
        snapshot.candidate &&
          Map.take(snapshot.candidate, [:id, :claim_generation, :digest, :status, :created_at]),
      evaluation: snapshot.evaluation,
      actors:
        Enum.map(snapshot.actors, fn actor ->
          Map.take(actor, [:role, :revision, :state, :skills, :updated_at])
        end),
      pulses:
        Enum.map(snapshot.pulses, fn pulse ->
          %{
            id: pulse.id,
            role: pulse.role,
            number: pulse.number,
            status: pulse.status,
            output: pulse.output,
            started_at: pulse.started_at,
            finished_at: pulse.finished_at
          }
        end),
      events: Enum.map(snapshot.events, &Map.take(&1, [:seq, :type, :data, :created_at]))
    }
  end

  defp model_id(%{id: id}), do: id
  defp model_id(value) when is_binary(value), do: value
  defp model_id(_), do: nil

  defp usage(value) when is_map(value) do
    value
    |> Map.take([
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cached_tokens,
      :total_tokens,
      :total_cost,
      :input_cost,
      :output_cost
    ])
    |> Map.new(fn {key, item} -> {to_string(key), scalar(item)} end)
  end

  defp usage(_), do: nil
  defp error(nil), do: nil
  defp error(value), do: inspect(value, limit: 20, printable_limit: 1_000)

  defp scalar(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: value

  defp scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar(value), do: inspect(value, limit: 20, printable_limit: 1_000)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
