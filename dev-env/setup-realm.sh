#!/bin/bash
# Setup Bondy realm for CortexIQ

REALM_URI="be.cortexiq.energy"
BONDY_API="http://localhost:18081"

echo "🔧 Setting up Bondy realm: $REALM_URI"

# Check if Bondy is running
if ! curl -s "$BONDY_API/realms" > /dev/null 2>&1; then
  echo "❌ Bondy is not running! Please start it with: docker compose up -d"
  exit 1
fi

# Check if realm exists and delete it to recreate with correct settings
if curl -s "$BONDY_API/realms/$REALM_URI" > /dev/null 2>&1; then
  echo "⚠️  Realm $REALM_URI exists, deleting to recreate with security disabled..."
  curl -X DELETE "$BONDY_API/realms/$REALM_URI" > /dev/null 2>&1
  sleep 1
fi

# Create realm with security disabled (allows anonymous connections)
echo "📝 Creating realm with security disabled..."

# Create config file
cat > /tmp/cortexiq-realm.json << 'EOFCONFIG'
{
  "uri": "be.cortexiq.energy",
  "description": "CortexIQ Energy Trading Simulation Realm - Macula Platform Demo",
  "security_enabled": false,
  "allow_private_subnet": true
}
EOFCONFIG

curl -X POST "$BONDY_API/realms" \
  -H "Content-Type: application/json" \
  -d @/tmp/cortexiq-realm.json > /dev/null 2>&1

rm -f /tmp/cortexiq-realm.json

if curl -s "$BONDY_API/realms/$REALM_URI" > /dev/null 2>&1; then
  echo "✅ Realm created successfully!"
else
  echo "❌ Failed to create realm"
  exit 1
fi
