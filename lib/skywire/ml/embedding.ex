defmodule Skywire.ML.Embedding do
  use Supervisor
  require Logger

  # Standard efficient embedding model (~384 dim)
  def model_name, do: "sentence-transformers/all-MiniLM-L6-v2"

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Loading embedding model: #{model_name()}...")
    
    auth_token = System.get_env("HF_TOKEN")
    opts = if auth_token, do: [auth_token: auth_token], else: []

    # Load model and tokenizer from HuggingFace
    {:ok, model_info} = Bumblebee.load_model({:hf, model_name()}, opts)
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_name()}, opts)

    # Create a serving process with EXLA compilation
    # Mean pooling gives us a single vector per sentence
    serving =
      Bumblebee.Text.text_embedding(model_info, tokenizer,
        output_pool: :mean_pooling,
        output_attribute: :hidden_state,
        compile: [batch_size: 32, sequence_length: 128],
        defn_options: [compiler: EXLA]
      )

    children = [
      # 1. Ingestion Serving: Optimized for throughput (firehose)
      #    Longer timeout to allow batches to fill up.
      Nx.Serving.child_spec(
        name: Skywire.EmbeddingServing.Ingest,
        serving: serving,
        batch_timeout: 100
      ),

      # 2. API Serving: Optimized for latency (search queries)
      #    Short timeout to respond ASAP.
      Nx.Serving.child_spec(
        name: Skywire.EmbeddingServing.API,
        serving: serving,
        batch_timeout: 10
      ),
      
      # 3. Webhook Matcher
      Skywire.Matcher
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Generates an embedding vector for the given text.
  Usage: generate(text, :api) or generate(text, :ingest)
  """
  def generate(text, type \\ :api) 
  
  def generate(text, type) when is_binary(text) do
    serving = serving_name(type)
    
    try do
      result = Nx.Serving.batched_run(serving, text)
      
      result.embedding
      |> Nx.to_flat_list()
    rescue
      e ->
        Logger.error("Embedding generation error for '#{text}': #{inspect(e)}")
        nil
    end
  end
  
  def generate(_, _), do: nil

  @doc """
  Generates embeddings for a list of texts.
  Defaults to :ingest serving for high throughput.
  """
  def generate_batch(texts, type \\ :ingest) when is_list(texts) do
    serving = serving_name(type)
    results = Nx.Serving.batched_run(serving, texts)
    
    # Results is a list of maps: [%{embedding: tensor}, ...]
    results
    |> Enum.map(fn %{embedding: tensor} ->
      Nx.to_flat_list(tensor)
    end)
  end
  
  defp serving_name(:api), do: Skywire.EmbeddingServing.API
  defp serving_name(:ingest), do: Skywire.EmbeddingServing.Ingest
end
