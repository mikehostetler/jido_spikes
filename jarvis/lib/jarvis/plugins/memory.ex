defmodule Jarvis.Plugins.Memory do
  @moduledoc "Connects Agent memory operations to one configured local store."
  use Jido.Plugin, option_keys: [agent: [:namespace, :store]]

  @impl true
  def prepare(_preparation, opts), do: configuration(opts)

  @impl true
  def derive_routes(_data) do
    [
      route("jarvis.memory.recall", :recall),
      route("jarvis.memory.remember", :remember)
    ]
  end

  @doc false
  def configuration(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, namespace} <- Keyword.fetch(opts, :namespace),
         :ok <- validate_namespace(namespace),
         {:ok, store} <- Keyword.fetch(opts, :store),
         :ok <- validate_store(store) do
      {:ok, %{namespace: namespace, store: store}}
    else
      false -> invalid_configuration(:options, opts)
      :error -> invalid_configuration(:options, :required)
      {:error, _reason} = error -> error
    end
  end

  def configuration(opts), do: invalid_configuration(:options, opts)

  @doc false
  def prepared_configuration(context) when is_map(context) do
    case get_in(context, [:plugin_inputs, __MODULE__]) do
      %Jido.Plugin.Input{prepared: %{namespace: namespace, store: store} = config}
      when is_binary(namespace) and is_atom(store) ->
        {:ok, config}

      _other ->
        {:error, Jido.Error.execution_error("Memory Plugin configuration is unavailable")}
    end
  end

  @doc false
  def recall(context, text, opts \\ []) do
    with {:ok, %{namespace: namespace, store: store}} <- prepared_configuration(context) do
      {:ok, store.recall(namespace, text, opts)}
    end
  end

  @doc false
  def remember(context, attrs) do
    with {:ok, %{namespace: namespace, store: store}} <- prepared_configuration(context) do
      store.remember(Map.put(attrs, :namespace, namespace))
    end
  end

  defp validate_namespace(namespace) when is_binary(namespace) do
    if String.trim(namespace) == "",
      do: invalid_configuration(:namespace, namespace),
      else: :ok
  end

  defp validate_namespace(namespace), do: invalid_configuration(:namespace, namespace)

  defp validate_store(store) when is_atom(store) do
    if Code.ensure_loaded?(store) and function_exported?(store, :recall, 3) and
         function_exported?(store, :remember, 1) do
      :ok
    else
      invalid_configuration(:store, store)
    end
  end

  defp validate_store(store), do: invalid_configuration(:store, store)

  defp invalid_configuration(field, value) do
    {:error,
     Jido.Error.validation_error("Memory Plugin options are invalid",
       kind: :config,
       field: field,
       details: %{field => value}
     )}
  end

  defp route(path, operation) do
    %{
      path: path,
      handler: %{kind: :action, target: Jarvis.Actions.Memory},
      defaults: %{operation: operation},
      state: :unchanged,
      reply: %{type: path <> ".response", from: %{source: :output, path: []}}
    }
  end
end
