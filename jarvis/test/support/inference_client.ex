defmodule Jarvis.TestInferenceClient do
  @moduledoc false
  @behaviour Jido.AI.InferenceClient

  def generate_text(model, context, _options) do
    if owner = Application.get_env(:jarvis, :test_inference_owner) do
      send(owner, {:model_request, model, context})
    end

    case Application.get_env(:jarvis, :test_inference_result, {:ok, "Offline VSM review"}) do
      {:ok, text} ->
        {:ok,
         %ReqLLM.Response{
           id: "jarvis-test-response",
           model: model,
           context: context,
           finish_reason: :stop,
           message: ReqLLM.Context.assistant(text)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stream_text(_model, _context, _options), do: {:error, :unsupported}
  def generate_object(_model, _context, _schema, _options), do: {:error, :unsupported}
  def generate_image(_model, _prompt, _options), do: {:error, :unsupported}
  def stream_image(_model, _prompt, _options), do: {:error, :unsupported}
  def generate_video(_model, _content, _options), do: {:error, :unsupported}
  def query_video(_model, _task_id, _options), do: {:error, :unsupported}
  def wait_video(_model, _task_id, _options), do: {:error, :unsupported}
  def retrieve_video_file(_model, _file_id, _options), do: {:error, :unsupported}
  def upload_video_file(_model, _file, _options), do: {:error, :unsupported}
  def stream_object(_model, _context, _schema, _options), do: {:error, :unsupported}
  def embed(_model, _input, _options), do: {:error, :unsupported}
  def rerank(_model, _options), do: {:error, :unsupported}
  def compact_context(_model, _context, _options), do: {:error, :unsupported}
  def evaluate(_model, _state, _questions, _options), do: {:error, :unsupported}
  def evaluation_models, do: []
  def ocr(_model, _document, _options), do: {:error, :unsupported}
  def ocr_file(_model, _path, _options), do: {:error, :unsupported}
  def transcribe(_model, _audio, _options), do: {:error, :unsupported}
  def transcribe_detailed(_model, _audio, _options), do: {:error, :unsupported}
  def speak(_model, _text, _options), do: {:error, :unsupported}
  def speak_detailed(_model, _text, _options), do: {:error, :unsupported}
end
