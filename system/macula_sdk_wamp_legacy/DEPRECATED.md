# ⚠️ DEPRECATED - WAMP-Based SDK

**This SDK has been replaced and is no longer maintained.**

## Migration Path

This SDK was built for the legacy WAMP/Bondy architecture and has been **replaced** by the new HTTP/3-based SDK.

### New SDK Location

The active SDK is now located at:

**Repository:** [macula/apps/macula_sdk](https://github.com/macula-io/macula/tree/main/apps/macula_sdk)

**Language:** Erlang (works in both Erlang and Elixir)

**Transport:** HTTP/3 (QUIC) instead of WAMP/WebSocket

### Why This Change?

1. **Architecture Shift:** Macula platform moved from WAMP/Bondy to HTTP/3 mesh networking
2. **Better Performance:** QUIC provides better NAT traversal and connection resilience
3. **Standards-Based:** HTTP/3 is an IETF standard with broad tooling support
4. **Language Consistency:** Erlang SDK matches the platform language

### What to Do?

If you're using this legacy SDK:

1. **Stop using this SDK** - It will not receive updates
2. **Migrate to the new SDK** - See [macula/apps/macula_sdk/README.md](https://github.com/macula-io/macula/blob/main/apps/macula_sdk/README.md)
3. **Update your code** - The API is similar but transport is different

### Quick Comparison

| Feature | Legacy (WAMP) | New (HTTP/3) |
|---------|---------------|---------------|
| Language | Elixir | Erlang |
| Transport | WebSocket | QUIC/HTTP3 |
| Protocol | WAMP | Macula Protocol |
| Router | Bondy | Macula Mesh |
| Status | ⚠️ Deprecated | ✅ Active |

### Need Help?

See the new SDK documentation:
- [README.md](https://github.com/macula-io/macula/blob/main/apps/macula_sdk/README.md)
- [Macula Architecture](https://github.com/macula-io/macula-architecture)

---

**Deprecated on:** 2025-11-09
**Replaced by:** macula/apps/macula_sdk
