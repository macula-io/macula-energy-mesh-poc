#!/bin/bash
# Bootstrap Bondy with authentication and security
# Creates admin users and configures RBAC

set -e

BONDY_URL="http://hub.macula.local/admin"
BONDY_REALM="com.leapsight.bondy"

# Credentials (change these!)
ADMIN_USER="admin"
ADMIN_PASSWORD="${BONDY_ADMIN_PASSWORD:-macula-admin-2025}"
CONSOLE_USER="console"
CONSOLE_PASSWORD="${BONDY_CONSOLE_PASSWORD:-macula-console-2025}"
APP_USER="cortexiq"
APP_PASSWORD="${BONDY_APP_PASSWORD:-macula-app-2025}"

echo "========================================="
echo "Bondy Security Bootstrap"
echo "========================================="
echo ""
echo "⚠️  IMPORTANT: Save these credentials!"
echo ""
echo "Admin User:"
echo "  Username: $ADMIN_USER"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "Console User:"
echo "  Username: $CONSOLE_USER"
echo "  Password: $CONSOLE_PASSWORD"
echo ""
echo "Application User:"
echo "  Username: $APP_USER"
echo "  Password: $APP_PASSWORD"
echo ""
echo "========================================="
echo ""

# Wait for Bondy to be ready
echo "Checking Bondy availability..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" "$BONDY_URL/status" | grep -q "200"; then
    echo "✓ Bondy is ready"
    break
  fi
  echo "Waiting for Bondy... ($i/30)"
  sleep 2
done

echo ""
echo "Creating master realm (com.leapsight.bondy)..."
curl -s -X POST "$BONDY_URL/realms" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "com.leapsight.bondy",
    "description": "Bondy Master Realm",
    "authmethods": ["wampcra", "trust"],
    "security_enabled": true
  }' | jq -r '.uri // "Already exists"'

echo ""
echo "Creating application realm (be.cortexiq.energy)..."
curl -s -X POST "$BONDY_URL/realms" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "be.cortexiq.energy",
    "description": "CortexIQ Energy Trading Application",
    "authmethods": ["wampcra", "trust"],
    "security_enabled": true
  }' | jq -r '.uri // "Already exists"'

echo ""
echo "Creating admin user..."
curl -s -X POST "$BONDY_URL/realms/com.leapsight.bondy/users" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"$ADMIN_USER\",
    \"password\": \"$ADMIN_PASSWORD\",
    \"groups\": [\"administrators\"],
    \"authorized_keys\": []
  }" | jq -r '.username // "Already exists"'

echo ""
echo "Creating console user..."
curl -s -X POST "$BONDY_URL/realms/com.leapsight.bondy/users" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"$CONSOLE_USER\",
    \"password\": \"$CONSOLE_PASSWORD\",
    \"groups\": [\"administrators\"],
    \"authorized_keys\": []
  }" | jq -r '.username // "Already exists"'

echo ""
echo "Creating application user for CortexIQ realm..."
curl -s -X POST "$BONDY_URL/realms/be.cortexiq.energy/users" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"$APP_USER\",
    \"password\": \"$APP_PASSWORD\",
    \"groups\": [\"developers\"],
    \"authorized_keys\": []
  }" | jq -r '.username // "Already exists"'

echo ""
echo "Granting permissions to application user..."
curl -s -X POST "$BONDY_URL/realms/be.cortexiq.energy/grants" \
  -H "Content-Type: application/json" \
  -d "{
    \"permissions\": [
      {\"uri\": \"*\", \"match\": \"prefix\", \"permissions\": [\"publish\", \"subscribe\", \"call\", \"register\"]}
    ],
    \"resources\": [
      {\"uri\": \"be.cortexiq.energy\"}
    ]
  }" || echo "Permissions may already exist"

echo ""
echo "========================================="
echo "✓ Bondy security configured successfully!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Update console credentials (will be done automatically)"
echo "2. Update application credentials in deployment secrets"
echo ""
echo "Test login:"
echo "  Console: http://console.macula.local"
echo "  Username: $CONSOLE_USER"
echo "  Password: $CONSOLE_PASSWORD"
echo "  Realm: com.leapsight.bondy"
