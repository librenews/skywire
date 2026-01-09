defmodule Skywire.ML.Embedding do
  @moduledoc """
  Manages the Bumblebee serving for generating text embeddings.
  Uses efficient batching via Nx.Serving.
  """
  require Logger

  # Standard efficient embedding model (~384 dim)
  def model_name, do: "sentence-transformers/all-MiniLM-L6-v2"

  def child_spec(_opts) do
    Logger.info("Loading embedding model: #{model_name()}...")
    
    # Load model and tokenizer from HuggingFace
    {:ok, model_info} = Bumblebee.load_model({:hf, model_name()})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_name()})

    # Create a serving process with EXLA compilation
    # Mean pooling gives us a single vector per sentence
    serving =
      Bumblebee.Text.text_embedding(model_info, tokenizer,
        output_pool: :mean_pooling,
        output_attribute: :hidden_state,
        compile: [batch_size: 16, sequence_length: 128],
        defn_options: [compiler: EXLA]
      )

    # Return the child spec for the serving process
    Nx.Serving.child_spec(
      name: Skywire.EmbeddingServing,
      serving: serving,
      batch_timeout: 100
    )
  end

  @doc """
  Generates an embedding vector for the given text.
  Returns a list of floats (size 384).
  """
  def generate(text) when is_binary(text) do
    result = Nx.Serving.batched_run(Skywire.EmbeddingServing, text)
    
    result.embedding
    |> Nx.to_flat_list()
  end
  
  def generate(_), do: nil

  @doc """
  Generates embeddings for a list of texts.
  Returns a list of vectors (lists of floats).
  """
  def generate_batch(texts) when is_list(texts) do
    result = Nx.Serving.batched_run(Skywire.EmbeddingServing, texts)
    
    # Result.embedding is a tensor (batch_size, 384)
    # converting to list of lists
    result.embedding
    |> Nx.to_batched(1)
    |> Enum.map(&(&1 |> Nx.squeeze() |> Nx.to_flat_list()))
  end
end
