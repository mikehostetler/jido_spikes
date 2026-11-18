defmodule Kura.Cell.Control.Adapter do
  @moduledoc false
  @behaviour Jido.VSM.Adapter
  alias Jido.VSM.Adapter.Default

  @impl true
  defdelegate s1_report(operation, payload), to: Default
  @impl true
  defdelegate s2_coordination(params), to: Default
  @impl true
  defdelegate s3_star_verify(kind, params), to: Default
  @impl true
  defdelegate s4_recommendation(role, params), to: Default
  @impl true
  defdelegate s5_policy(policy), to: Default

  @impl true
  def s3_command(params), do: "kura:#{params.operation}:#{params.request_id}"
end
