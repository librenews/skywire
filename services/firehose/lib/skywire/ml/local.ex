defmodule Skywire.ML.Local do
  @moduledoc """
  Local Inference Server using Bumblebee and EXLA (GPU).
  Generates text embeddings using BAAE/bge-large-en-v1.5.
  
  Includes circuit breaker and retry logic to handle transient GPU errors.
  """
  @behaviour Skywire.ML
  use GenServer
  require Logger

  @serving_name Skywire.ML.Serving

  # Circuit breaker thresholds
  @max_consecutive_failures 5
  @circuit_timeout_ms 60_000  # 60 seconds
  @max_retries 3

  defmodule State do
    defstruct consecutive_failures: 0,
              circuit_open: false,
              last_failure_time: nil,
              total_failures: 0,
              total_successes: 0
  end

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
    {:ok, %State{}}
  end

  @doc """
  Generates embeddings for a batch of texts.
  Returns nil if circuit breaker is open or all retries fail.
  """
  def generate_batch(texts, _model \\ nil) do
    GenServer.call(__MODULE__, {:generate_batch, texts}, 30_000)
  end

  @doc """
  Get current circuit breaker state for monitoring.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  ## GenServer Callbacks

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:generate_batch, texts}, _from, state) do
    # Check circuit breaker
    if state.circuit_open do
      if should_close_circuit?(state) do
        Logger.info("Circuit breaker: Attempting to close (half-open state)")
        # Try one request to test if service recovered
        {result, new_state} = attempt_generation_with_retry(texts, state)
        {:reply, result, new_state}
      else
        time_left = @circuit_timeout_ms - (System.monotonic_time(:millisecond) - state.last_failure_time)
        Logger.warning("Circuit breaker OPEN - skipping embedding generation (#{div(time_left, 1000)}s remaining)")
        {:reply, nil, state}
      end
    else
      # Circuit closed - process normally
      {result, new_state} = attempt_generation_with_retry(texts, state)
      {:reply, result, new_state}
    end
  end

  ## Private Functions

  defp attempt_generation_with_retry(texts, state) do
    case generate_with_retry(texts, @max_retries) do
      {:ok, embeddings} ->
        new_state = record_success(state)
        {embeddings, new_state}
      
      {:error, reason} ->
        new_state = record_failure(state, reason)
        {nil, new_state}
    end
  end

  defp generate_with_retry(texts, attempts_left) when attempts_left > 0 do
    try do
      output = Nx.Serving.batched_run(@serving_name, texts)
      
      # Extract embeddings from output
      embeddings = Enum.map(output, fn result -> 
        result.embedding 
        |> Nx.to_flat_list()
      end)
      
      {:ok, embeddings}
    catch
      kind, error ->
        error_msg = Exception.format(kind, error, __STACKTRACE__)
        
        if attempts_left > 1 do
          # Calculate backoff: 100ms, 200ms, 400ms
          backoff_ms = 100 * (2 ** (@max_retries - attempts_left))
          Logger.warning("GPU inference failed (#{kind}), retrying in #{backoff_ms}ms (#{attempts_left - 1} retries left)")
          Logger.debug("Error details: #{error_msg}")
          
          :timer.sleep(backoff_ms)
          generate_with_retry(texts, attempts_left - 1)
        else
          Logger.error("GPU inference failed after #{@max_retries} attempts: #{error_msg}")
          {:error, {kind, error}}
        end
    end
  end

  defp record_success(state) do
    Logger.debug("GPU inference successful (consecutive failures reset)")
    %{state | 
      consecutive_failures: 0,
      circuit_open: false,
      total_successes: state.total_successes + 1
    }
  end

  defp record_failure(state, reason) do
    new_consecutive = state.consecutive_failures + 1
    now = System.monotonic_time(:millisecond)
    
    new_state = %{state | 
      consecutive_failures: new_consecutive,
      total_failures: state.total_failures + 1,
      last_failure_time: now
    }
    
    if new_consecutive >= @max_consecutive_failures do
      Logger.error("Opening circuit breaker after #{new_consecutive} consecutive GPU failures")
      Logger.error("Last error: #{inspect(reason)}")
      %{new_state | circuit_open: true}
    else
      new_state
    end
  end

  defp should_close_circuit?(state) do
    if state.last_failure_time do
      elapsed = System.monotonic_time(:millisecond) - state.last_failure_time
      elapsed >= @circuit_timeout_ms
    else
      true
    end
  end
end
