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
    # Load model and tokenizer from HuggingFace
    # We use a helper to catch 403 errors and print helpful instructions
    {:ok, model_info} = load_resource(:model, model_name(), opts)
    {:ok, tokenizer} = load_resource(:tokenizer, model_name(), opts)
      
    # Create a serving process with EXLA compilation
    # Mean pooling gives us a single vector per sentence
    serving =
      Bumblebee.Text.text_embedding(model_info, tokenizer,
        output_pool: :mean_pooling,
        output_attribute: :hidden_state,
        compile: [batch_size: 64, sequence_length: 96],
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
    
    # Add a timeout to prevent indefinite hangs (e.g. if EXLA deadlocks)
    # 60s should be plenty for a batch of 25-100 items.
    # Note: batched_run takes (serving, batch/input) - it doesn't accept options directly in v0.6?
    # Actually wait, Nx.Serving.batched_run(serving, batch) is the signature.
    # There is no timeout option in batched_run/2.
    # It relies on GenServer.call default timeout (5000ms) but Nx.Serving might override it.
    
    # Wait, if it hangs properly, it means it's STUCK inside the serving process computation.
    # Using Task.await with timeout is a way to force it.
    
    task = Task.async(fn -> 
      Nx.Serving.batched_run(serving, texts)
    end)
    
    case Task.yield(task, 60_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, results} ->
        # Results is a list of maps: [%{embedding: tensor}, ...]
        results
        |> Enum.map(fn %{embedding: tensor} ->
          Nx.to_flat_list(tensor)
        end)
        
      nil ->
        Logger.error("Embedding generation timed out (60s). Killing process.")
        raise "Embedding generation timeout"
    end
  end
  
  defp serving_name(:api), do: Skywire.EmbeddingServing.API
  defp serving_name(:ingest), do: Skywire.EmbeddingServing.Ingest

  defp load_resource(type, name, opts) do
    loader = if type == :model, do: &Bumblebee.load_model/2, else: &Bumblebee.load_tokenizer/2
    
    # Bumblebee expects auth_token inside the {:hf, ...} tuple options, NOT as a 2nd arg.
    # We call load_model({:hf, name, opts}, [])
    case loader.({:hf, name, opts}, []) do
      {:ok, resource} -> {:ok, resource}
      {:error, reason} ->
        if String.contains?(inspect(reason), "403") do
          Logger.error("""
          
          ==================================================
          ❌ HUGGING FACE AUTHENTICATION ERROR (403)
          ==================================================
          Failed to download #{type}: #{name}
          
          The Hugging Face API rejected the request. This usually means:
          1. Your IP is being rate-limited.
          2. The HF_TOKEN environment variable is invalid/expired.
          3. You are missing an HF_TOKEN.

          ACTION REQUIRED:
          Please generate a User Access Token (Read) at:
          https://huggingface.co/settings/tokens
          
          And add it to your .env file:
          HF_TOKEN=hf_...
          ==================================================
          """)
        else
          Logger.error("Failed to load #{type} #{name}: #{inspect(reason)}")
        end
        recraise(reason)
    end
  end

  defp recraise(reason) do
    # We must crash to stop startup, but we want the log to be seen first.
    Process.sleep(100) 
    raise "Model loading failed: #{inspect(reason)}"
  end
end
