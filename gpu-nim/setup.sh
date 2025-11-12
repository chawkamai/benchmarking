#!/bin/bash
set -e

### === CONFIGURABLE VARIABLES ===
REPO_URL="https://github.com/chawkamai/benchmarking.git"
REPO_DIR="benchmarking/gpu-nim"
VENV_DIR="python-venv"
NVIDIA_DRIVER_URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/580.95.05/NVIDIA-Linux-x86_64-580.95.05.run"
SECRETS_DIR="/secrets"
CHECK_INTERVAL=15  # seconds between status checks
### ==============================

echo "Starting setup process..."

# --- Validate required environment variables ---
if [ -z "$HF_TOKEN" ]; then
  echo "Error: HF_TOKEN environment variable not set."
  echo "Usage: HF_TOKEN=your_hf_token NGC_API_KEY=your_ngc_key ./setup.sh"
  exit 1
fi

if [ -z "$NGC_API_KEY" ]; then
  echo "Error: NGC_API_KEY environment variable not set."
  echo "Usage: HF_TOKEN=your_hf_token NGC_API_KEY=your_ngc_key ./setup.sh"
  exit 1
fi

# --- Clone repo if not already cloned ---
if [ ! -d "$REPO_DIR" ]; then
  git clone "$REPO_URL"
fi
cd "$REPO_DIR"

# --- Bootstrap environment ---
./bootstrap.sh
source "$VENV_DIR/bin/activate"

# --- Install NVIDIA driver silently ---
echo "Installing NVIDIA driver..."
wget -q "$NVIDIA_DRIVER_URL" -O nvidia-driver.run
chmod +x nvidia-driver.run
bash nvidia-driver.run --silent --disable-nouveau --no-questions --no-nouveau-check --no-opengl-files

# --- Create secrets directory and write tokens ---
echo "Setting up secrets..."
mkdir -p "$SECRETS_DIR"
echo "$HF_TOKEN" > "$SECRETS_DIR/hf-token.txt"
echo "$NGC_API_KEY" > "$SECRETS_DIR/ngc-api-key.txt"

# --- Run docker setup scripts ---
echo "Running docker setup scripts..."
for f in docker/*; do
  bash "$f"
done

# --- Run nvidia setup scripts ---
echo "Running nvidia setup scripts..."
for f in nvidia/*; do
  bash "$f"
done

# --- Run getting-started with retry logic ---
echo "Running 'make getting-started'..."
if make getting-started; then
  echo "getting-started completed successfully."
else
  echo "⚠getting-started failed. Checking inference-server health..."
  while true; do
    STATUS=$(make status | grep -i 'inference-server' || true)
    echo "$STATUS"
    if echo "$STATUS" | grep -q '(healthy)'; then
      echo "inference-server is healthy. Bringing up containers..."
      make up
      break
    fi
    echo "Waiting for inference-server to become healthy..."
    sleep "$CHECK_INTERVAL"
  done
fi

echo "Setup complete."
