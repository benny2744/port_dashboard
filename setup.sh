#!/bin/bash
###############################################################################
# setup.sh - Install and start the port dashboard
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Port Dashboard Setup ==="
echo ""

# 1. Make refresh script executable
chmod +x "${SCRIPT_DIR}/scripts/refresh-data.sh"
echo "✓ Made refresh script executable"

# 2. Run initial data refresh
echo "→ Generating initial port data..."
"${SCRIPT_DIR}/scripts/refresh-data.sh"

# 3. Start the web server
echo "→ Starting web server container..."
cd "${SCRIPT_DIR}"
docker compose down 2>/dev/null || true
docker compose up -d

# 4. Install systemd timer (requires sudo)
echo ""
echo "=== Systemd Timer Installation ==="
echo "Run these commands with sudo to enable hourly refresh:"
echo ""
echo "  echo \"PORT_DASHBOARD_DIR=${SCRIPT_DIR}\" | sudo tee /etc/default/port-dashboard >/dev/null"
echo "  sudo cp ${SCRIPT_DIR}/systemd/port-dashboard-refresh.service /etc/systemd/system/"
echo "  sudo cp ${SCRIPT_DIR}/systemd/port-dashboard-refresh.timer /etc/systemd/system/"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable --now port-dashboard-refresh.timer"
echo ""

# 5. Verify
echo "=== Verification ==="
sleep 2
if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3005/ | grep -q "200"; then
    echo "✓ Dashboard is running at http://127.0.0.1:3005/"
else
    echo "✗ Dashboard may not be responding yet, check docker logs"
fi

echo ""
echo "=== Done ==="
echo "Access the dashboard at: http://127.0.0.1:3005/"
echo "Or via your reverse proxy at: /ports/ (after nginx config)"




