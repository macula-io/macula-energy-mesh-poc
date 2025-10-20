defmodule MeshWamp.IntegrationTest do
  @moduledoc """
  Integration test for WAMP connection to Bondy.

  Run this manually with: mix test test/integration_test.exs

  Make sure Bondy is running: docker-compose up -d bondy
  """
  use ExUnit.Case
  require Logger

  @moduletag :integration

  setup do
    Logger.configure(level: :debug)
    :ok
  end

  test "connect to Bondy and exchange messages" do
    # Start client - use properly configured energy mesh realm
    {:ok, client} = MeshWamp.start_link(
      url: "ws://localhost:18080/ws",
      realm: "com.energy.mesh"
    )

    # Wait for connection
    Process.sleep(1000)

    # Check status
    %{status: status, session_id: session_id} = MeshWamp.status(client)
    assert status == :connected
    assert is_integer(session_id)

    Logger.info("Connected to Bondy, session: #{session_id}")

    # Subscribe to a test topic
    test_topic = "com.example.test.topic"
    test_pid = self()

    :ok = MeshWamp.subscribe(client, test_topic, fn topic, event_data ->
      send(test_pid, {:event_received, topic, event_data})
    end)

    # Wait for subscription
    Process.sleep(500)

    # Publish to the topic
    :ok = MeshWamp.publish(client, test_topic, ["Hello", "World"], %{"key" => "value"})

    # Wait for event
    assert_receive {:event_received, ^test_topic, event_data}, 2000

    Logger.info("Received event: #{inspect(event_data)}")

    # Verify event data
    assert %{args: args, kwargs: kwargs} = event_data
    assert args == ["Hello", "World"]
    assert kwargs == %{"key" => "value"}

    # Cleanup
    MeshWamp.stop(client)
  end
end
