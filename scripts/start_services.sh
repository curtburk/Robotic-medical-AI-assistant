#!/bin/bash
# ──────────────────────────────────────────────
# Consent Agent — Full Demo Launcher
# ──────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

# Auto-detect this machine's IP (prefer non-loopback, non-docker)
ZGX_IP=$(hostname -I | awk '{print $1}')
if [ -z "$ZGX_IP" ]; then
    ZGX_IP="localhost"
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  🩺 Medical Triage Demo"
echo "══════════════════════════════════════════════"
echo ""

# ── Step 1: Stop any existing services ──
echo "  [1/6] Cleaning up old processes..."
lsof -ti:8080 2>/dev/null | xargs kill -9 2>/dev/null || true
docker stop zgx-ai-api 2>/dev/null || true
docker rm zgx-ai-api 2>/dev/null || true
curl -sf -X POST http://reachy-mini.local:8000/api/apps/stop-current-app > /dev/null 2>&1 || true
sleep 2
echo "         ✅ Clean"
echo ""

# ── Step 2: Start Docker API container ──
echo "  [2/6] Starting AI API container..."
docker run --rm -d --name zgx-ai-api --gpus all --network host \
    -e WHISPER_MODEL_SIZE=small \
    -v "$PROJECT_DIR/models:/models" \
    consent-agent:latest > /dev/null 2>&1
echo "         ✅ Container started"
echo ""

# ── Step 3: Wait for vLLM to load ──
echo "  [3/6] Waiting for LLM to load (this takes ~90 seconds)..."
SECONDS=0
while true; do
    if curl -sf http://localhost:8090/health > /dev/null 2>&1; then
        HEALTH=$(curl -sf http://localhost:8090/health)
        WHISPER_OK=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('whisper',False))" 2>/dev/null)
        LLM_OK=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('llm',False))" 2>/dev/null)
        TTS_OK=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tts',False))" 2>/dev/null)
        WHISPER_MODEL=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('whisper_model','?'))" 2>/dev/null)

        if [ "$LLM_OK" = "True" ] && [ "$WHISPER_OK" = "True" ] && [ "$TTS_OK" = "True" ]; then
            echo ""
            echo "         ✅ All systems ready (${SECONDS}s)"
            echo "            Whisper: ✓ ${WHISPER_MODEL}"
            echo "            LLM:     ✓ online"
            echo "            TTS:     ✓ online"
            break
        else
            printf "\r         ⏳ API up but waiting for components... (%ds)" $SECONDS
        fi
    else
        printf "\r         ⏳ Loading LLM... (%ds)                        " $SECONDS
    fi

    if [ $SECONDS -gt 300 ]; then
        echo ""
        echo "         ❌ Timed out after 5 minutes!"
        echo "         Check: docker logs zgx-ai-api -f"
        exit 1
    fi

    sleep 3
done
echo ""

# ── Step 4: Start dashboard web server ──
echo "  [4/6] Starting dashboard server..."
cd "$PROJECT_DIR"
python3 -m http.server 8080 > /dev/null 2>&1 &
DASHBOARD_PID=$!
sleep 1

# Verify dashboard is serving
if curl -sf -o /dev/null http://localhost:8080/index.html; then
    echo "         ✅ Dashboard serving on port 8080"
else
    echo "         ❌ Dashboard failed to start!"
    echo "         Check that index.html exists in: $PROJECT_DIR"
    exit 1
fi
echo ""

# ── Step 5: Start Reachy app ──
echo "  [5/6] Starting Reachy Mini app..."

# Update the robot's API URL to point to this machine
echo "         Setting ZGX_API_URL=http://${ZGX_IP}:8090 on robot..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 pollen@reachy-mini.local \
    "echo 'ZGX_API_URL=http://${ZGX_IP}:8090' | sudo tee /etc/environment > /dev/null" 2>/dev/null || \
    echo "         ⚠️  Could not update robot env (SSH). Using existing ZGX_API_URL."

curl -sf -X POST http://reachy-mini.local:8000/api/apps/start-app/consent_agent_reachy > /dev/null 2>&1 || true

# Give the app a moment to initialize and test ALSA
sleep 5

APP_STATUS=$(curl -sf http://reachy-mini.local:8000/api/apps/current-app-status 2>/dev/null) || APP_STATUS="unknown"
echo "         ✅ Reachy app launched (status: $APP_STATUS)"
echo ""

# ── Step 6: Final verification ──
echo "  [6/6] Final check..."
ALL_GOOD=true

if ! curl -sf http://localhost:8090/health > /dev/null 2>&1; then
    echo "         ❌ API not responding"
    ALL_GOOD=false
fi

if ! curl -sf -o /dev/null http://localhost:8080/index.html; then
    echo "         ❌ Dashboard not serving"
    ALL_GOOD=false
fi

if [ "$ALL_GOOD" = true ]; then
    echo "         ✅ All systems go!"
fi

echo ""
echo "══════════════════════════════════════════════"
echo ""
echo "  ✅ DEMO READY — Open the dashboard:"
echo ""
echo "     👉 http://${ZGX_IP}:8080/index.html"
echo ""
echo "  Speak to the Reachy Mini. The transcript"
echo "  will appear on the dashboard in real time."
echo ""
echo "══════════════════════════════════════════════"
echo ""
echo "  Ctrl+C to stop the dashboard server."
echo "  To stop everything:"
echo "    docker stop zgx-ai-api"
echo "    curl -X POST http://reachy-mini.local:8000/api/apps/stop-current-app"
echo ""

# ── Cleanup on exit ──
cleanup() {
    echo ""
    echo "  Stopping dashboard server..."
    kill $DASHBOARD_PID 2>/dev/null || true
    echo "  Dashboard stopped."
    echo "  API container and Reachy app still running."
    exit 0
}

trap cleanup INT TERM
wait $DASHBOARD_PID
