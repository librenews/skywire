defmodule Skywire.ML.Local do
  @moduledoc """
  Local Inference Server using Bumblebee and EXLA (GPU).
  Generates text embeddings using BAAE/bge-large-en-v1.5.
  """
  use GenServer
  require Logger

  @serving_name Skywire.ML.Serving
  @serving_name Skywire.ML.Serving

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    model_repo = Application.get_env(:skywire, :ml_model_repo, "BAAI/bge-large-en-v1.5")
    Logger.info("Initializing Local ML (Bumblebee) with model: #{model_repo}...")
    
    {:ok, model_info} = Bumblebee.load_model({:hf, model_repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_repo})
    
    serving =
      Bumblebee.Text.text_embedding(model_info, tokenizer,
        output_attribute: :pooled_state,
        compile: [batch_size: 16, sequence_length: 256],
        defn_options: [compiler: EXLA, client: :default]
      )

    Nx.Serving.start_link(name: @serving_name, serving: serving)

    Logger.info("Local ML Serving started successfully.")
    {:ok, %{}}
  end

  @doc """
  Generates embeddings for a batch of texts.
  """
  def generate_batch(texts, _model \\ nil) do
    # Note: _model arg is ignored as we currently serve one model locally,
    # but we keep arity for compatibility with Cloudflare contract.
    
    try do
      output = Nx.Serving.batched_run(@serving_name, texts)
      # Output is a LIST of maps: [%{encryption: tensor}, ...]
      # We need to extract the embedding from each and return a list of lists.
      Enum.map(output, fn result -> 
        # Bumblebee defaults the output key to :embedding or :pooled_state depending on version?
        # The error log showed keys: [:embedding]
        result.embedding 
        |> Nx.to_flat_list()
      end)
    rescue
      e -> 
        Logger.error("Local Inference Failed: #{inspect(e)}")
        nil
    end
  end
end
