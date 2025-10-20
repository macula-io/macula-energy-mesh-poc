# Testing Shutdown & Realm Cleanup

## The Problem with Development Mode

When running with `iex -S mix phx.server`, **Ctrl+C does NOT trigger application shutdown** - it goes to IEx instead. This means `terminate/2` callbacks won't be called, and realms won't be cleaned up.

## Testing Methods

### Method 1: Manual Shutdown from IEx (Recommended for Dev)

```bash
# Terminal 1: Start the hub
./test-local.sh

# Wait for startup, then in the IEx prompt:
iex> MeshHub.System.shutdown()

# You should see:
# [warning] Manual shutdown triggered from IEx
# [warning] ============================================================
# [warning] 🛑 INITIATING GRACEFUL SHUTDOWN
# [warning]   Reason: :manual
# [warning] ============================================================
# [warning] Calling Application.stop(:mesh_hub)...
# [warning] ============================================================
# [warning] MeshHub.Application.stop/1 called
# [warning]   Supervisor tree will now shutdown (children terminate in LIFO order)
# [warning] ============================================================
# [warning] ============================================================
# [warning] RealmManager.terminate/2 called
# [warning]   Reason: :shutdown
# [warning]   Realm: com.energy.mesh
# [warning]   Created by us: true
# [warning] ============================================================
# [warning] 🗑️  Deleting realm: com.energy.mesh (we created it)
# [warning] ✅ Successfully deleted realm: com.energy.mesh
# [warning] RealmManager.terminate/2 finished
```

### Method 2: Send SIGTERM to Process (Works in Background)

```bash
# Start in background (not interactive)
cd system
export BONDY_URL="ws://localhost:18080/ws"
export BONDY_REALM="com.energy.mesh"
export BONDY_ADMIN_URL="http://localhost:18081"
mix run --no-halt &
PID=$!

# Wait for startup
sleep 5

# Send SIGTERM
kill -TERM $PID

# Check logs for shutdown sequence
```

### Method 3: Docker (Production-like)

```bash
# Start via docker-compose
cd dev-env
docker-compose up mesh_hub_web

# In another terminal, stop gracefully
docker-compose stop mesh_hub_web

# Check logs
docker-compose logs mesh_hub_web | grep -E "(terminate|shutdown|Deleting realm)"
```

## Expected Shutdown Sequence

With proper logging, you should see:

```
1. [warning] 🛑 INITIATING GRACEFUL SHUTDOWN
2. [warning] Calling Application.stop(:mesh_hub)...
3. [warning] MeshHub.Application.stop/1 called
4. [warning] RealmManager.terminate/2 called
5. [warning] 🗑️  Deleting realm: com.energy.mesh (we created it)
6. [warning] ✅ Successfully deleted realm: com.energy.mesh
7. [warning] RealmManager.terminate/2 finished
```

## Verification

After shutdown, verify realm is deleted:

```bash
# Should return nothing (realm deleted)
curl -s http://localhost:18081/realms | jq '.[] | select(.uri == "com.energy.mesh")'
```

## Troubleshooting

### "Realm still exists after shutdown"

**Check if terminate/2 was called:**
Look for `RealmManager.terminate/2 called` in logs. If missing, the GenServer wasn't properly shut down.

**Check if realm was created by us:**
```elixir
iex> MeshHub.RealmManager.get_state()
%{created: false, ...}  # ← If false, we won't delete it
```

### "Ctrl+C doesn't trigger shutdown"

This is **expected in IEx mode**. Use `MeshHub.System.shutdown()` instead.

## IEx Development Workflow

```elixir
# Start
./test-local.sh

# When done, shutdown gracefully:
iex> MeshHub.System.shutdown()
# Wait 2 seconds
iex> System.halt(0)
```
