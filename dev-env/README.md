# Development Environment

## Current Status

### ✅ Step 1: App Dependencies
All umbrella app dependencies configured correctly.

### ✅ Step 2: Bondy Container
Bondy is running as a Docker container:
- HTTP API: http://localhost:18080
- Admin API: http://localhost:18081
- Raw TCP WAMP: localhost:18082
- WebSocket WAMP: **Needs configuration**

### ✅ Step 3: mesh_wamp WAMP Client
WAMP client library implemented with:
- `MeshWamp.Protocol` - WAMP message encoding/decoding
- `MeshWamp.Connection` - WebSocket connection management
- `MeshWamp.Client` - High-level pub/sub API

**Status**: Code complete and WebSocket connection working, but blocked by Bondy issue (see below).

## ✅ WAMP Connection - WORKING!

### Complete End-to-End Flow:
1. ✅ Bondy container running with bondy.conf mounted
2. ✅ WebSocket WAMP endpoint at `ws://localhost:18080/ws`
3. ✅ WebSocket subprotocol negotiation (`wamp.2.json`)
4. ✅ WAMP message encoding/decoding
5. ✅ HELLO/WELCOME handshake complete
6. ✅ Anonymous authentication working
7. ✅ Pub/Sub messaging verified
8. ✅ Bondy Console available at http://localhost:3000

### Authentication Solution:
The key to successful anonymous authentication is **proper realm configuration** with security sources.

Realm `com.energy.mesh` configured with:
- `"authmethods": ["anonymous"]`
- `"security_enabled": true` (required!)
- **Sources** defining who can authenticate:
  ```json
  {
    "usernames": ["anonymous"],
    "authmethod": "anonymous",
    "cidr": "0.0.0.0/0"
  }
  ```
- **Grants** giving anonymous role full WAMP permissions

HELLO message format:
```json
[1, "com.energy.mesh", {
  "authid": "anonymous",
  "authmethods": ["anonymous"],
  "roles": {"publisher": {}, "subscriber": {}}
}]
```

**Important**: You cannot disable security (`security_enabled: false`). Bondy requires security enabled with proper sources and grants configured.

## Development Environment Summary

The development infrastructure is **fully functional**:
- ✅ Umbrella app with 7 applications configured
- ✅ Bondy WAMP router running in Docker
- ✅ Bondy Console web UI available
- ✅ WAMP client library (mesh_wamp) implemented and tested
- ✅ WebSocket connections working
- ✅ Anonymous authentication configured
- ✅ End-to-end pub/sub messaging verified

**Status**: Ready for bot implementation!

## Running Bondy

```bash
cd dev-env
docker-compose up -d bondy bondy_console
docker logs -f mesh_bondy
```

Access Bondy Console: http://localhost:3000

## Dynamic Realm Management

**Important**: Realms are now created automatically by the hub when it starts!

The `com.energy.mesh` realm is created by `MeshHub.RealmManager` when mesh_hub starts, and is automatically deleted when the hub shuts down. This ensures realms are ephemeral and only exist when their hub is active.

### Manual Realm Creation (for testing without hub)

If you want to create the realm manually for testing, use this curl command:

```bash
curl -X POST 'http://localhost:18081/realms' -H 'Content-Type: application/json' -d '{
  "uri": "com.energy.mesh",
  "description": "Energy Mesh PoC realm",
  "authmethods": ["anonymous"],
  "security_enabled": true,
  "users": [],
  "groups": [],
  "sources": [
    {
      "usernames": ["anonymous"],
      "authmethod": "anonymous",
      "cidr": "0.0.0.0/0"
    }
  ],
  "grants": [
    {
      "permissions": [
        "wamp.register",
        "wamp.unregister",
        "wamp.subscribe",
        "wamp.unsubscribe",
        "wamp.call",
        "wamp.cancel",
        "wamp.publish"
      ],
      "uri": "*",
      "roles": ["anonymous"]
    }
  ]
}'
```

## Testing mesh_wamp

```bash
cd system
mix test apps/mesh_wamp/test/integration_test.exs
```

Expected output: Test passes with WAMP session established and pub/sub messages exchanged.
