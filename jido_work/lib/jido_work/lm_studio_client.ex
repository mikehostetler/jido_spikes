defmodule JidoWork.LMStudioClient do
  @moduledoc "A Jido inference client that selects one local LM Studio model per run."

  @behaviour Jido.AI.InferenceClient

  @process_key {__MODULE__, :model_id}

  def with_model(model_id, fun) when is_binary(model_id) and is_function(fun, 0) do
    previous = Process.get(@process_key)
    Process.put(@process_key, normalize_model_id(model_id))

    try do
      fun.()
    after
      if previous, do: Process.put(@process_key, previous), else: Process.delete(@process_key)
    end
  end

  def health do
    case Req.get("http://127.0.0.1:1234/v1/models", receive_timeout: 1_500, retry: false) do
      {:ok, %Req.Response{status: 200, body: %{"data" => models}}} ->
        ids = Enum.map(models, &Map.get(&1, "id")) |> Enum.reject(&is_nil/1)
        %{status: :online, models: ids, message: "LM Studio is online."}

      {:ok, %Req.Response{status: status}} ->
        %{status: :error, models: [], message: "LM Studio returned HTTP #{status}."}

      {:error, reason} ->
        %{
          status: :offline,
          models: [],
          message: "LM Studio is not available: #{Exception.message(reason)}"
        }
    end
  rescue
    error ->
      %{
        status: :offline,
        models: [],
        message: "LM Studio is not available: #{Exception.message(error)}"
      }
  end

  @impl true
  def generate_text(_model, context, options) do
    local_model = ReqLLM.model!(%{provider: :lmstudio, id: current_model_id()})
    Jido.AI.InferenceClient.ReqLLM.generate_text(local_model, context, options)
  end

  @impl true
  def stream_text(_model, context, options) do
    local_model = ReqLLM.model!(%{provider: :lmstudio, id: current_model_id()})
    Jido.AI.InferenceClient.ReqLLM.stream_text(local_model, context, options)
  end

  @impl true
  def evaluation_models, do: []

  @handled [generate_text: 3, stream_text: 3, evaluation_models: 0]

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      {name, arity} not in @handled do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
      do: {:error, :not_supported}
  end

  defp current_model_id do
    Process.get(@process_key) || System.get_env("LMSTUDIO_MODEL") || "qwen3.8-27b-mlx"
  end

  defp normalize_model_id("lmstudio:" <> model_id), do: model_id
  defp normalize_model_id(model_id), do: model_id
end
