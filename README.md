# Reachy Mini Medical Triage Voice Agent

A fully local, on-premise medical triage voice assistant running on an HP ZGX Nano and Pollen Robotics Reachy Mini robot. No cloud APIs - all inference happens on local hardware.

The robot greets patients, listens to their symptoms, asks follow-up questions, and provides triage guidance - all through natural voice conversation with expressive antenna and head movements. A live dashboard displays the transcript in real time for clinical observation.

---

## Architecture

```
┌──────────────────────┐         HTTP          ┌─────────────────────────────────────┐
│     Reachy Mini      │ ◄──────────────────►  │       HP ZGX Nano (Docker)          │
│                      │                        │                                     │
│  Mic (ALSA) ─────────┤── POST /process ──────►│  faster-whisper (STT, CPU)          │
│                      │                        │  Llama-3.1-8B-Instruct-AWQ (LLM)   │
│  Speaker ◄───────────┤◄── WAV response ──────│  Piper TTS (speech synthesis)       │
│                      │                        │                                     │
│  Antennas / Head     │                        │  /conversations ──► Live Dashboard  │
└──────────────────────┘                        └─────────────────────────────────────┘
```

## Performance

| Stage | Time | Notes |
|-------|------|-------|
| Recording | ~3-4s | VAD-based chunking, stops on silence |
| Whisper STT | ~2-3s | large-v3-turbo on CPU, int8 |
| LLM response | ~0.5-1s | AWQ INT4, Marlin kernels |
| Piper TTS | <1s | aarch64 binary |
| **Total** | **~5-7s** | From end of speech to hearing response |

## Hardware

- **HP ZGX Nano** - NVIDIA GB10 GPU, runs all AI inference
- **Reachy Mini** - Pollen Robotics robot with USB mic/speaker, head servos, antenna motors
- Both on the same local network (192.168.xx.x)

## Software Stack

| Component | Technology | Details |
|-----------|-----------|---------|
| STT | faster-whisper (large-v3-turbo) | CTranslate2, CPU int8, Silero VAD |
| LLM | Llama-3.1-8B-Instruct-AWQ-INT4 | vLLM with AWQ Marlin kernels |
| TTS | Piper | en_US-lessac-medium voice |
| API | FastAPI | Runs inside Docker on ZGX Nano |
| Robot App | reachy-mini SDK | Deployed via HuggingFace Spaces |
| Dashboard | Vanilla HTML/JS | Polls API for live transcript |

## Directory Structure

```
consent-agent/
├── docker/
│   ├── Dockerfile.api          # Docker image for the AI API
│   └── zgx_ai_api.py           # FastAPI server (STT + LLM + TTS)
├── hf-space/
│   ├── consent_agent_reachy/
│   │   └── main.py             # Reachy Mini app (recording, playback, expressions)
│   ├── pyproject.toml           # Package config for HF Spaces
│   └── deploy_to_hf.sh         # Deploy script
├── models/
│   ├── Llama-3.1-8B-Instruct-AWQ-INT4/   # Quantized LLM
│   ├── piper-tts/
│   │   └── en_US-lessac-medium.onnx       # TTS voice model
│   └── Llama-3.1-8B-UltraMedical/        # Full-precision medical LLM (backup)
├── scripts/
│   └── start_services.sh       # One-command demo launcher
├── index.html                   # Live transcript dashboard
└── README.md
```

## Quick Start

### Prerequisites

- Docker with NVIDIA GPU support on the ZGX Nano
- Reachy Mini on the same network (default: `reachy-mini.local`)
- Models downloaded to `~/Desktop/consent-agent/models/`

### Build (one time)

```bash
cd ~/Desktop/consent-agent/docker
docker build -t consent-agent:latest -f Dockerfile.api .
```

### Run

```bash
cd ~/Desktop/consent-agent/scripts
./start_services.sh
```

The script will:
1. Clean up any existing processes
2. Start the Docker API container
3. Wait for Whisper, LLM, and TTS to be ready (~90 seconds)
4. Start the dashboard web server
5. Launch the Reachy Mini app
6. Verify all systems and print a clickable dashboard link

When you see `✅ DEMO READY`, open the dashboard URL and speak to the robot.

### Stop

```bash
# Stop everything
docker stop zgx-ai-api
curl -X POST http://reachy-mini.local:8000/api/apps/stop-current-app
# Dashboard stops with Ctrl+C in the terminal
```

---

## Demo Script

### Setup (5 minutes before demo)

1. Power on the ZGX Nano and Reachy Mini
2. Open a terminal on the ZGX Nano (or SSH in)
3. Run `./start_services.sh` and wait for `✅ DEMO READY`
4. Open the dashboard link in a browser on your laptop
5. Verify the dashboard shows **System Online** with green checkmarks

### Talking Points

> "This is a fully local medical triage voice agent. There are no cloud APIs involved — all speech recognition, language understanding, and speech synthesis run on this HP ZGX Nano using NVIDIA GPU acceleration. The robot uses a quantized Llama 3.1 model for medical reasoning, Whisper for speech recognition, and Piper for text-to-speech. Let me show you how it works."

### Demo Conversation

The robot will greet the patient on startup: *"Hi there! I'm your medical triage assistant. How can I help you today?"*

**You say:** "I've been having really bad back pain for about four days."

> *Expected response: The assistant will acknowledge the back pain, note the 4-day duration, and ask follow-up questions — likely about severity, location, and what makes it better or worse.*

**You say:** "It's about a 7 out of 10 on the pain scale. It's in my lower back."

> *Expected response: The assistant will note the severity and location, and may ask about what triggered it or if you have other symptoms.*

**You say:** "I was lifting heavy boxes at work and felt a sharp pain."

> *Expected response: The assistant will connect the lifting to the injury and likely recommend seeing a doctor, possibly mentioning risk of a muscle strain or disc issue.*

**You say:** "Should I go to the emergency room?"

> *Expected response: The assistant will provide guidance based on the symptoms described — for 4-day back pain from lifting, it will likely recommend seeing a doctor but not necessarily the ER unless there are red-flag symptoms.*

**You say:** "Okay, thank you for your help."

> *Expected response: A polite closing, reminding the patient to follow up with their doctor.*

### Dashboard Walkthrough

While the conversation happens, point out:
- The **live transcript** appearing in real time on the dashboard
- The **Patient ID** assigned to the session
- The **System Status** panel showing all components are healthy
- The **Export** buttons — "Export as Medical Record" creates a timestamped text file that could be attached to a patient's chart

### Key Points for the Audience

- **Fully on-premise** — no data leaves the local network. Critical for healthcare (HIPAA), government, and defense use cases.
- **Air-gapped capable** — works with no internet connection after initial setup.
- **Sub-7-second response time** — natural conversational pace.
- **Medically appropriate responses** — the LLM provides triage-level guidance, not diagnosis.
- **Expressive robot** — antenna and head movements give visual feedback on the robot's state (listening, thinking, speaking).
- **Live dashboard** — clinicians can observe the conversation in real time and export records.

---

## Updating the Robot App

After editing `main.py`, push changes without a full redeploy:

```bash
scp ~/Desktop/consent-agent/hf-space/consent_agent_reachy/main.py \
  pollen@reachy-mini.local:/venvs/apps_venv/lib/python3.12/site-packages/consent_agent_reachy/main.py
ssh pollen@reachy-mini.local "rm -rf /venvs/apps_venv/lib/python3.12/site-packages/consent_agent_reachy/__pycache__"
curl -X POST http://reachy-mini.local:8000/api/apps/stop-current-app
sleep 3
curl -X POST http://reachy-mini.local:8000/api/apps/start-app/consent_agent_reachy
```

## Troubleshooting

### Robot not responding to speech

- Check ALSA device: `ssh pollen@reachy-mini.local "arecord -D reachymini_audio_src -f S16_LE -r 16000 -c 2 -d 3 /tmp/test.wav"`
- Check robot logs: `ssh pollen@reachy-mini.local "sudo journalctl -u reachy-mini-daemon -f --since 'now'"`
- Check API health: `curl http://localhost:8090/health`

### Poor transcription accuracy

- Verify Whisper model: `curl -s http://localhost:8090/health | python3 -c "import sys,json; print(json.load(sys.stdin))"`
- `large-v3-turbo` is recommended for accuracy; `small` is faster but less accurate
- Override at runtime: `docker run ... -e WHISPER_MODEL_SIZE=large-v3-turbo ...`

### LLM slow or unresponsive

- Check vLLM is using AWQ Marlin: `docker logs zgx-ai-api 2>&1 | grep -i "awq\|marlin"`
- Ensure `--quantization awq_marlin` is in the Dockerfile CMD

### Dashboard shows "Disconnected"

- Verify the API is running: `curl http://localhost:8090/health`
- Check CORS is enabled in `zgx_ai_api.py`
- Ensure the dashboard HTML can reach the API (same network, port 8090 open)

### Left antenna overload error

- This is a hardware issue — the antenna motor is jammed or hitting resistance
- The voice agent will continue to work; the error is non-fatal
- Physically check the antenna for obstructions

## Network Details

| Device | Address | Ports |
|--------|---------|-------|
| ZGX Nano | Auto-detected by `start_services.sh` | 8090 (API), 8080 (Dashboard) |
| Reachy Mini | reachy-mini.local | 8000 (Daemon API) |

The launch script auto-detects the ZGX Nano's IP and updates the robot's `ZGX_API_URL` environment variable via SSH. No hardcoded IPs - just connect both devices to the same network and run the script.

If the robot can't resolve the ZGX Nano, manually set the env var:
```bash
ssh pollen@reachy-mini.local "echo 'ZGX_API_URL=http://<ZGX_IP>:8090' | sudo tee /etc/environment"
```

## Robot Access

```
SSH:      ssh pollen@reachy-mini.local  (password: root)
App dir:  /venvs/apps_venv/lib/python3.12/site-packages/consent_agent_reachy/
Daemon:   systemctl status reachy-mini-daemon
Logs:     sudo journalctl -u reachy-mini-daemon -f
```
