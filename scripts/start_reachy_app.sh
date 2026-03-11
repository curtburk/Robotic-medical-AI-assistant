
#!/bin/bash
echo "Waking up robot..."
curl -sf -X POST http://reachy-mini.local:8000/api/daemon/start?wake_up=true
sleep 10
echo "Starting consent agent..."
curl -sf -X POST http://reachy-mini.local:8000/api/apps/start-app/consent_agent_reachy
echo "Done. Watch logs with:"
echo "  ssh pollen@reachy-mini.local 'sudo journalctl -u reachy-mini-daemon -f'"

chmod +x ~/Desktop/consent-agent/scripts/start_reachy_app.sh