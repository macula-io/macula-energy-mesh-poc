defmodule MaculaSdk.Wamp.Protocol do
  @moduledoc """
  WAMP protocol message types and encoding/decoding.

  WAMP uses JSON for message serialization.
  Each message is a JSON array: [MESSAGE_TYPE, ...args]
  """

  # WAMP message types
  @hello 1
  @welcome 2
  @abort 3
  @goodbye 6
  @error 8
  @publish 16
  @published 17
  @subscribe 32
  @subscribed 33
  @unsubscribe 34
  @unsubscribed 35
  @event 36
  @call 48
  @result 50
  @register 64
  @registered 65
  @invocation 68
  @yield 70

  # Message type constants
  def hello, do: @hello
  def welcome, do: @welcome
  def abort, do: @abort
  def goodbye, do: @goodbye
  def error, do: @error
  def publish, do: @publish
  def published, do: @published
  def subscribe, do: @subscribe
  def subscribed, do: @subscribed
  def unsubscribe, do: @unsubscribe
  def unsubscribed, do: @unsubscribed
  def event, do: @event
  def call, do: @call
  def result, do: @result
  def register, do: @register
  def registered, do: @registered
  def invocation, do: @invocation
  def yield, do: @yield

  @doc """
  Encode a WAMP message to JSON string.
  """
  def encode(message) when is_list(message) do
    Jason.encode!(message)
  end

  @doc """
  Decode a JSON string to WAMP message.
  """
  def decode(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, message} when is_list(message) -> {:ok, message}
      {:error, _} = error -> error
      _ -> {:error, :invalid_message}
    end
  end

  @doc """
  Build a HELLO message.

  HELLO: [1, realm, details]
  """
  def hello_message(realm, details \\ %{}) do
    [@hello, realm, details]
  end

  @doc """
  Build a PUBLISH message.

  PUBLISH: [16, request_id, options, topic, args, kwargs]
  """
  def publish_message(request_id, topic, args \\ [], kwargs \\ %{}, options \\ %{}) do
    [@publish, request_id, options, topic, args, kwargs]
  end

  @doc """
  Build a SUBSCRIBE message.

  SUBSCRIBE: [32, request_id, options, topic]
  """
  def subscribe_message(request_id, topic, options \\ %{}) do
    [@subscribe, request_id, options, topic]
  end

  @doc """
  Build a GOODBYE message.

  GOODBYE: [6, details, reason]
  """
  def goodbye_message(reason \\ "wamp.close.normal", details \\ %{}) do
    [@goodbye, details, reason]
  end

  @doc """
  Build a CALL message (RPC call).

  CALL: [48, request_id, options, procedure, args, kwargs]
  """
  def call_message(request_id, procedure, args \\ [], kwargs \\ %{}, options \\ %{}) do
    [@call, request_id, options, procedure, args, kwargs]
  end

  @doc """
  Build a REGISTER message (register RPC endpoint).

  REGISTER: [64, request_id, options, procedure]
  """
  def register_message(request_id, procedure, options \\ %{}) do
    [@register, request_id, options, procedure]
  end

  @doc """
  Build a YIELD message (return RPC result).

  YIELD: [70, invocation_request_id, options, args, kwargs]
  """
  def yield_message(invocation_request_id, args \\ [], kwargs \\ %{}, options \\ %{}) do
    [@yield, invocation_request_id, options, args, kwargs]
  end

  @doc """
  Build an ERROR message.

  ERROR: [8, request_type, request_id, details, error_uri, args, kwargs]
  """
  def error_message(request_type, request_id, error_uri, args \\ [], kwargs \\ %{}, details \\ %{}) do
    # Convert request_type atom to WAMP message type integer
    request_type_id = case request_type do
      :invocation -> @invocation
      :call -> @call
      :subscribe -> @subscribe
      :register -> @register
      other when is_integer(other) -> other
      _ -> 0
    end

    [@error, request_type_id, request_id, details, error_uri, args, kwargs]
  end

  @doc """
  Parse a WAMP message and return its type and components.
  """
  def parse_message([type | _rest] = message) do
    case type do
      @welcome -> parse_welcome(message)
      @abort -> parse_abort(message)
      @goodbye -> parse_goodbye(message)
      @error -> parse_error(message)
      @published -> parse_published(message)
      @subscribed -> parse_subscribed(message)
      @event -> parse_event(message)
      @registered -> parse_registered(message)
      @result -> parse_result(message)
      @invocation -> parse_invocation(message)
      _ -> {:unknown, message}
    end
  end

  defp parse_welcome([@welcome, session_id, details]) do
    {:welcome, %{session_id: session_id, details: details}}
  end

  defp parse_abort([@abort, details, reason]) do
    {:abort, %{details: details, reason: reason}}
  end

  defp parse_goodbye([@goodbye, details, reason]) do
    {:goodbye, %{details: details, reason: reason}}
  end

  defp parse_error([@error, request_type, request_id, details, error_uri | rest]) do
    args = Enum.at(rest, 0, [])
    kwargs = Enum.at(rest, 1, %{})

    {:error, %{
      request_type: request_type,
      request_id: request_id,
      details: details,
      error_uri: error_uri,
      args: args,
      kwargs: kwargs
    }}
  end

  defp parse_published([@published, request_id, publication_id]) do
    {:published, %{request_id: request_id, publication_id: publication_id}}
  end

  defp parse_subscribed([@subscribed, request_id, subscription_id]) do
    {:subscribed, %{request_id: request_id, subscription_id: subscription_id}}
  end

  defp parse_event([@event, subscription_id, publication_id, details | rest]) do
    args = Enum.at(rest, 0, [])
    kwargs = Enum.at(rest, 1, %{})

    {:event, %{
      subscription_id: subscription_id,
      publication_id: publication_id,
      details: details,
      args: args,
      kwargs: kwargs
    }}
  end

  defp parse_registered([@registered, request_id, registration_id]) do
    {:registered, %{request_id: request_id, registration_id: registration_id}}
  end

  defp parse_result([@result, request_id, details | rest]) do
    args = Enum.at(rest, 0, [])
    kwargs = Enum.at(rest, 1, %{})

    {:result, %{
      request_id: request_id,
      details: details,
      args: args,
      kwargs: kwargs
    }}
  end

  defp parse_invocation([@invocation, invocation_request_id, registration_id, details | rest]) do
    args = Enum.at(rest, 0, [])
    kwargs = Enum.at(rest, 1, %{})

    {:invocation, %{
      invocation_request_id: invocation_request_id,
      registration_id: registration_id,
      details: details,
      args: args,
      kwargs: kwargs
    }}
  end
end
