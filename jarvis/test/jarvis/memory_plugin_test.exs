defmodule Jarvis.MemoryPluginTest do
  use ExUnit.Case, async: true

  alias Jarvis.Actions.Memory, as: MemoryAction
  alias Jarvis.Plugins.Memory

  defmodule TestStore do
    @behaviour Jarvis.Memory.Store

    @impl true
    def recall(namespace, text, _opts) do
      [%{id: 7, title: namespace, content: text, class: "semantic"}]
    end

    @impl true
    def remember(attrs), do: {:ok, %{id: attrs.namespace}}
  end

  test "the Action uses the configured store and namespace" do
    context = memory_context(TestStore, "configured")

    assert {:ok,
            %{
              memories: [
                %{id: 7, title: "configured", content: "find this", class: "semantic"}
              ]
            }} = MemoryAction.run(%{operation: :recall, text: "find this"}, context)

    assert {:ok, %{id: "configured"}} =
             MemoryAction.run(
               %{
                 operation: :remember,
                 text: "store this",
                 title: "Test memory",
                 class: "semantic"
               },
               context
             )
  end

  test "invalid or unavailable configuration fails before a store call" do
    assert {:error, _error} = Memory.configuration([])
    assert {:error, _error} = Memory.configuration(namespace: " ", store: TestStore)
    assert {:error, _error} = Memory.configuration(namespace: "test", store: String)

    assert {:error, _error} =
             MemoryAction.run(%{operation: :recall, text: "find this"}, %{})
  end

  defp memory_context(store, namespace) do
    %{
      plugin_inputs: %{
        Memory => %Jido.Plugin.Input{prepared: %{store: store, namespace: namespace}}
      }
    }
  end
end
