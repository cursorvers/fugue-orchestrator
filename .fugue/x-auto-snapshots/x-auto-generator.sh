#!/bin/bash
# x-auto auto generator + image generation launcher for launchd (daily 06:00 JST)
set -euo pipefail
source "$(dirname "$0")/x-auto-env.sh"
x_auto_load_secrets XAI_API_KEY GEMINI_API_KEY

SCRIPT_DIR="$HOME/.local/share/x-auto"

cd /tmp || exit 1

# Step 1: Generate draft posts from trends
/opt/homebrew/bin/python3 "${SCRIPT_DIR}/auto_generator.py"

# Step 2: Generate images for posts missing image_path (draft or approved)
export GEMINI_API_KEY
/opt/homebrew/bin/node "${SCRIPT_DIR}/scripts/generate-images-nb2.js" 2>&1 || true
