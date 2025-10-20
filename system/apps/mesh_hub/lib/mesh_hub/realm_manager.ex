defmodule MeshHub.RealmManager do
  @moduledoc """
  Manages the lifecycle of WAMP realms in Bondy.

  Creates the realm when the hub starts and removes it when the hub shuts down.
  This ensures realms are ephemeral and only exist when their hub is active.
  """
  use GenServer
  require Logger

  defstruct [:realm_uri, :bondy_admin_url, :created]

  @realm_config %{
    "description" => "Energy Mesh PoC realm - real-time energy trading simulation",
    "authmethods" => ["anonymous"],
    "security_enabled" => true,
    "users" => [],
    "groups" => [],
    "sources" => [
      %{
        "usernames" => ["anonymous"],
        "authmethod" => "anonymous",
        "cidr" => "0.0.0.0/0",
        "meta" => %{
          "description" => "Allow all clients to connect anonymously from any network"
        }
      }
    ],
    "grants" => [
      %{
        "permissions" => [
          "wamp.register",
          "wamp.unregister",
          "wamp.subscribe",
          "wamp.unsubscribe",
          "wamp.call",
          "wamp.cancel",
          "wamp.publish"
        ],
        "uri" => "*",
        "roles" => ["anonymous"],
        "meta" => %{
          "description" => "Grant all WAMP permissions to anonymous users for PoC"
        }
      }
    ]
  }

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_realm_uri do
    GenServer.call(__MODULE__, :get_realm_uri)
  end

  @doc """
  Get the current state of the realm manager (for debugging).
  Returns: %{realm_uri: String.t(), created: boolean(), bondy_admin_url: String.t()}
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    realm_uri = Keyword.get(opts, :realm_uri, "com.energy.mesh")
    bondy_admin_url = Keyword.get(opts, :bondy_admin_url, "http://localhost:18081")

    # Trap exits to ensure terminate/2 is called on shutdown
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      realm_uri: realm_uri,
      bondy_admin_url: bondy_admin_url,
      created: false
    }

    # Create realm asynchronously
    send(self(), :create_realm)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_realm_uri, _from, state) do
    {:reply, state.realm_uri, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply,
     %{
       realm_uri: state.realm_uri,
       created: state.created,
       bondy_admin_url: state.bondy_admin_url
     }, state}
  end

  @impl true
  def handle_info(:create_realm, state) do
    case create_realm(state.realm_uri, state.bondy_admin_url) do
      :ok ->
        Logger.info("✅ Created realm: #{state.realm_uri}")
        {:noreply, %{state | created: true}}

      {:error, :already_exists} ->
        Logger.warning("⚠️  Realm already exists: #{state.realm_uri} (will NOT delete on shutdown)")
        # Don't mark as created since we didn't create it - don't delete what we didn't create
        {:noreply, %{state | created: false}}

      {:error, reason} ->
        Logger.error("Failed to create realm: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), :create_realm, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning("=" <> String.duplicate("=", 60))
    Logger.warning("RealmManager.terminate/2 called")
    Logger.warning("  Reason: #{inspect(reason)}")
    Logger.warning("  Realm: #{state.realm_uri}")
    Logger.warning("  Created by us: #{state.created}")
    Logger.warning("=" <> String.duplicate("=", 60))

    if state.created do
      Logger.warning("🗑️  Deleting realm: #{state.realm_uri} (we created it)")

      case delete_realm(state.realm_uri, state.bondy_admin_url) do
        :ok ->
          Logger.warning("✅ Successfully deleted realm: #{state.realm_uri}")

        {:error, reason} ->
          Logger.error("❌ Failed to delete realm: #{inspect(reason)}")
      end
    else
      Logger.warning("ℹ️  Realm #{state.realm_uri} was not created by this manager - skipping deletion")
    end

    Logger.warning("RealmManager.terminate/2 finished")
    :ok
  end

  ## Private Functions

  defp create_realm(realm_uri, bondy_admin_url) do
    url = "#{bondy_admin_url}/realms"
    body = Map.put(@realm_config, "uri", realm_uri)

    case Req.post(url, json: body) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 409}} ->
        # Already exists (HTTP 409 Conflict)
        {:error, :already_exists}

      {:ok, %{status: 400, body: %{"code" => "bondy.error.already_exists"}}} ->
        # Already exists (Bondy returns 400 with error code)
        {:error, :already_exists}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to create realm, status: #{status}, body: #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Failed to create realm: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp delete_realm(realm_uri, bondy_admin_url) do
    url = "#{bondy_admin_url}/realms/#{realm_uri}"

    case Req.delete(url) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 404}} ->
        # Already deleted
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("Failed to delete realm, status: #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("Failed to delete realm: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
