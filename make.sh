#!/bin/bash
#
# Oxygen Flow — one-shot installer for Apple Silicon Macs.
#
#   git clone https://github.com/evangandy/Oxygen-Flow.git
#   cd Oxygen-Flow
#   ./make.sh
#
# This does EVERYTHING: installs the toolchain (Command Line Tools, Homebrew, cmake),
# installs & starts Ollama, pulls the cleanup model, downloads the Whisper speech model,
# builds the app, installs it to /Applications, enables it at login, and walks you
# through the one-time macOS permissions. Safe to re-run (it skips finished steps).
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CYAN='\033[1;36m'; GREEN='\033[1;32m'; YEL='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
step() { printf "\n${CYAN}==> %s${NC}\n" "$1"; }
ok()   { printf "${GREEN}✓ %s${NC}\n" "$1"; }
warn() { printf "${YEL}! %s${NC}\n" "$1"; }

APP_NAME="Oxygen Flow"
BUNDLE_ID="com.oxygenflow.app"
CLEANUP_MODEL="qwen2.5:3b-instruct"
WHISPER_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
SUPPORT_DIR="$HOME/Library/Application Support/OxygenFlow"
MODEL_DIR="$SUPPORT_DIR/models"
WHISPER_MODEL="$MODEL_DIR/ggml-large-v3-turbo.bin"

# ── 0. Platform ───────────────────────────────────────────────────────────────
if [ "$(uname -m)" != "arm64" ]; then
  echo "This installer targets Apple Silicon (arm64) Macs. Yours is $(uname -m)."; exit 1
fi

# ── 1. Xcode Command Line Tools ───────────────────────────────────────────────
step "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  warn "Not installed — a system dialog will open. Finish it, then re-run ./make.sh"
  xcode-select --install || true
  exit 1
fi
ok "present"

# ── 2. Homebrew ───────────────────────────────────────────────────────────────
step "Homebrew"
if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ]; then
  warn "Installing Homebrew (you may be asked for your password)…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
ok "ready"

# ── 3. cmake + Ollama ─────────────────────────────────────────────────────────
step "cmake + Ollama"
brew list cmake  >/dev/null 2>&1 || brew install cmake
brew list ollama >/dev/null 2>&1 || brew install ollama
ok "installed"

# ── 4. Start Ollama (also enables it at login) ────────────────────────────────
step "Starting Ollama"
brew services start ollama >/dev/null 2>&1 || ollama serve >/tmp/oxygen-ollama.log 2>&1 &
for _ in $(seq 1 30); do
  curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
  sleep 1
done
curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 || { echo "Ollama didn't come up — see /tmp/oxygen-ollama.log"; exit 1; }
ok "running"

# ── 5. Cleanup model ──────────────────────────────────────────────────────────
step "Cleanup model ($CLEANUP_MODEL, ~2 GB)"
ollama pull "$CLEANUP_MODEL"
ok "ready"

# ── 6. Whisper speech model ───────────────────────────────────────────────────
step "Whisper speech model (~1.5 GB)"
mkdir -p "$MODEL_DIR"
if [ -f "$WHISPER_MODEL" ]; then
  ok "already downloaded"
else
  curl -L --fail --progress-bar -o "$WHISPER_MODEL.part" "$WHISPER_URL"
  mv "$WHISPER_MODEL.part" "$WHISPER_MODEL"
  ok "downloaded"
fi

# ── 7. Build whisper.cpp static libraries (Metal) ─────────────────────────────
step "Building whisper.cpp (Metal)"
if [ -f "vendor/whisper.cpp/build/src/libwhisper.a" ]; then
  ok "already built"
else
  bash scripts/build_whisper.sh
  ok "built"
fi

# ── 8. Build the app ──────────────────────────────────────────────────────────
step "Building $APP_NAME"
bash scripts/build_app.sh release
ok "built"

# ── 9. Install to /Applications ───────────────────────────────────────────────
step "Installing to /Applications"
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_NAME.app" "/Applications/"
ok "installed"

# ── 10. Configure (model path, cleanup model, launch at login) ────────────────
step "Configuring $APP_NAME"
defaults write "$BUNDLE_ID" whisperModelPath "$WHISPER_MODEL"
defaults write "$BUNDLE_ID" ollamaModel "$CLEANUP_MODEL"
defaults write "$BUNDLE_ID" launchAtLogin -bool true
ok "configured"

# ── 11. Launch + one-time permissions ─────────────────────────────────────────
step "Launching $APP_NAME"
open "/Applications/$APP_NAME.app"
sleep 2

printf "\n${GREEN}${BOLD}Done!${NC} $APP_NAME is running — look for the chevron in your menu bar.\n\n"
printf "${BOLD}Two one-time permissions macOS requires for any dictation app:${NC}\n"
printf "  1) ${BOLD}Accessibility${NC} — for the global hotkey + pasting into apps.\n"
printf "     Opening that settings pane now — flip on \"$APP_NAME\".\n"
printf "  2) ${BOLD}Microphone${NC} — you'll be asked the first time you dictate. Click Allow.\n\n"
printf "Hotkey: ${BOLD}Control + ~${NC}  (press to start, press again to stop)\n\n"

open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
ok "setup complete"
