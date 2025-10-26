defmodule MaculaOs.Proxy.WebSocketHandler do
  @moduledoc """
  WebSocket handler for WAMP proxy connections from application containers.

  Applications connect to localhost:8080 and this handler:
  1. Authenticates via API key in WAMP HELLO message
  2. Proxies valid WAMP messages to upstream Bondy connection
  3. Meters usage (pub/sub operations)
  4. Enforces namespace/topic restrictions
  """
  @behaviour WebSock

  require Logger

  defstruct [
    :client_id,
    :api_key,
    :namespace,
    :upstream_pid,
    :authenticated,
    :pending_requests
  ]

  @impl true
  def init(_opts) do
    client_id = generate_client_id()
    Logger.info("New WAMP client connection: #{client_id}")

    state = %__MODULE__{
      client_id: client_id,
      api_key: nil,
      namespace: nil,
      upstream_pid: nil,
      authenticated: false,
      pending_requests: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_in({text, opcode: :text}, state) do
    case Jason.decode(text) do
      {:ok, message} when is_list(message) ->
        handle_wamp_message(message, state)

      {:error, reason} ->
        Logger.warning("Invalid JSON from client #{state.client_id}: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_in(_message, state) do
    # Ignore non-text frames
    {:ok, state}
  end

  @impl true
  def handle_info({:upstream, message}, state) do
    # Message from upstream Bondy - forward to client
    case Jason.encode(message) do
      {:ok, json} ->
        {:push, {:text, json}, state}

      {:error, reason} ->
        Logger.error("Failed to encode upstream message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_info({:disconnect, reason}, state) do
    Logger.info("Client #{state.client_id} disconnecting: #{reason}")
    {:stop, :normal, state}
  end

  def handle_info(_message, state) do
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Client #{state.client_id} terminated: #{inspect(reason)}")

    # Notify upstream of disconnection
    if state.upstream_pid do
      send(state.upstream_pid, {:client_disconnected, state.client_id})
    end

    :ok
  end

  # WAMP Message Handling

  defp handle_wamp_message([1 | _] = hello_msg, state) do
    # WAMP HELLO message - authenticate
    handle_hello(hello_msg, state)
  end

  defp handle_wamp_message(message, %{authenticated: false} = state) do
    # Not authenticated yet - reject
    Logger.warning("Unauthenticated message from #{state.client_id}: #{inspect(message)}")
    error = [8, 0, %{}, "wamp.error.not_authorized"]

    case Jason.encode(error) do
      {:ok, json} ->
        {:push, [{:text, json}, :close], state}

      _ ->
        {:stop, :normal, state}
    end
  end

  defp handle_wamp_message(message, state) do
    # Authenticated - proxy to upstream
    proxy_to_upstream(message, state)
  end

  defp handle_hello([1, _realm, details], state) do
    # Extract API key from authextra
    api_key = get_in(details, ["authextra", "macula_apikey"])

    if api_key do
      # Validate API key using Auth module
      case MaculaOs.Auth.ApiKey.validate(api_key) do
        {:ok, namespace, _metadata} ->
          Logger.info("Client #{state.client_id} authenticated as namespace: #{namespace}")

          # Get or create upstream connection
          {:ok, upstream_pid} = MaculaOs.Proxy.Upstream.get_connection()

          # Register this client with upstream
          send(upstream_pid, {:client_connected, state.client_id, self()})

          # Send WELCOME message
          welcome = [2, generate_session_id(), %{
            "agent" => "MaculaOs-Proxy/0.1.0",
            "roles" => %{
              "broker" => %{},
              "dealer" => %{}
            }
          }]

          state = %{state |
            api_key: api_key,
            namespace: namespace,
            upstream_pid: upstream_pid,
            authenticated: true
          }

          case Jason.encode(welcome) do
            {:ok, json} ->
              {:push, {:text, json}, state}

            _ ->
              {:stop, :normal, state}
          end

        {:error, reason} ->
          # Invalid API key
          Logger.warning("Client #{state.client_id} authentication failed: #{reason}")
          abort = [3, %{}, "wamp.error.not_authorized"]

          case Jason.encode(abort) do
            {:ok, json} ->
              {:push, [{:text, json}, :close], state}

            _ ->
              {:stop, :normal, state}
          end
      end
    else
      # No API key - reject
      Logger.warning("Client #{state.client_id} missing API key")
      abort = [3, %{}, "wamp.error.not_authorized"]

      case Jason.encode(abort) do
        {:ok, json} ->
          {:push, [{:text, json}, :close], state}

        _ ->
          {:stop, :normal, state}
      end
    end
  end

  defp proxy_to_upstream(message, state) do
    # Extract operation and topic for validation/metering
    {operation, topic} = extract_operation_and_topic(message)

    # Validate topic prefix matches namespace
    if topic && not MaculaOs.Auth.ApiKey.allowed_topic?(state.namespace, topic) do
      Logger.warning("Client #{state.client_id} attempted access to unauthorized topic: #{topic}")

      error = [8, 0, %{}, "wamp.error.not_authorized", ["Topic not allowed for namespace"]]

      case Jason.encode(error) do
        {:ok, json} ->
          {:push, {:text, json}, state}

        _ ->
          {:ok, state}
      end
    else
      # Record operation for metering
      if operation do
        MaculaOs.Metering.record(state.api_key, operation, topic)
      end

      # Forward to upstream
      send(state.upstream_pid, {:proxy_message, state.client_id, message})

      {:ok, state}
    end
  end

  # Helpers

  defp generate_client_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_session_id do
    :rand.uniform(9_007_199_254_740_992)  # Max safe integer for WAMP
  end

  defp extract_operation_and_topic(message) do
    case message do
      [16 | _] -> {:publish, extract_topic_from_publish(message)}
      [32 | _] -> {:subscribe, extract_topic_from_subscribe(message)}
      [48 | _] -> {:call, extract_procedure_from_call(message)}
      _ -> {nil, nil}
    end
  end

  defp extract_topic_from_publish([16, _request_id, _options, topic | _]), do: topic
  defp extract_topic_from_publish(_), do: nil

  defp extract_topic_from_subscribe([32, _request_id, _options, topic | _]), do: topic
  defp extract_topic_from_subscribe(_), do: nil

  defp extract_procedure_from_call([48, _request_id, _options, procedure | _]), do: procedure
  defp extract_procedure_from_call(_), do: nil
end
