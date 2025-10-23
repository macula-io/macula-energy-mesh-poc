#!/bin/bash
set -e

echo "Updating realm configuration..."

kubectl --context kind-macula-hub exec -n macula-hub deployment/bondy -- \
  curl -s -X PUT http://localhost:18081/realms/be.cortexiq.energy \
  -H "Content-Type: application/json" \
  -d @- <<'EOF'
{
  "description": "CortexIQ Energy Trading Demo Realm",
  "is_prototype": false,
  "is_sso_realm": false,
  "security_enabled": false,
  "allow_connections": true,
  "authmethods": ["anonymous"]
}
EOF

echo ""
echo "Verifying realm configuration..."

kubectl --context kind-macula-hub exec -n macula-hub deployment/bondy -- \
  curl -s http://localhost:18081/realms/be.cortexiq.energy | python3 -m json.tool

echo ""
echo "Done!"
