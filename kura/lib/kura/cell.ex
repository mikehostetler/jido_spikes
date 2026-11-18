defmodule Kura.Cell do
  @moduledoc "Defines a reusable Durable Work Cell and its child slots."

  defmacro __using__(opts) do
    options =
      opts
      |> Jido.Agent.DSL.prepare_options!(__CALLER__)
      |> Jido.Agent.DSL.prepend_plugin(Jido.VSM.Cell.Plugin)
      |> Jido.Agent.DSL.prepend_plugin(Kura.Cell.Plugin)

    quote do
      use Jido.Agent, unquote(Macro.escape(options))
      import Jido.VSM.Cell.Plugin, only: [vsm: 1]

      def pulse_handlers, do: %{}
      def playbook_tasks, do: %{}
      defoverridable pulse_handlers: 0, playbook_tasks: 0
    end
  end

  def profile(%Jido.Agent{plugins: plugins}) do
    case Enum.find(plugins, &(&1.provider == Kura.Cell.Plugin)) do
      %{data: data} -> {:ok, data}
      nil -> {:error, :missing_cell_definition}
    end
  end
end
