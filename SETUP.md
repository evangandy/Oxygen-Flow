# Setup guide for Claude Code (or any coding agent)

This file exists so an agent can set up and run Oxygen Flow end-to-end without a
human doing anything but approving permission prompts. Follow it top to bottom.

## Preconditions

- Apple Silicon Mac (M1 or later), macOS 14+. Check with `uname -m` — must print `arm64`.
  If it prints `x86_64`, stop: this build does not support Intel Macs.
- Repo cloned with submodules. If `vendor/whisper.cpp/CMakeLists.txt` doesn't exist, run:
  ```bash
  git submodule update --init --recursive
  ```

## Run the installer

```bash
./make.sh
```

This single script is idempotent (safe to re-run, skips finished steps) and does
everything:

1. Fetches the `vendor/whisper.cpp` submodule if missing.
2. Installs Xcode Command Line Tools (opens a system dialog if missing — this step
   requires a human to click through; if it exits asking for that, tell the user and
   wait, then re-run `./make.sh`).
3. Installs Homebrew if missing.
4. `brew install cmake ollama`.
5. Starts the Ollama daemon (`brew services start ollama`) and waits for it to answer
   on `http://127.0.0.1:11434`.
6. `ollama pull qwen2.5:3b-instruct` — the local cleanup model (~2GB).
7. Downloads the Whisper speech model (`ggml-large-v3-turbo.bin`, ~1.5GB) to
   `~/Library/Application Support/OxygenFlow/models/`.
8. Builds whisper.cpp's static libraries with Metal (`scripts/build_whisper.sh`).
9. Creates a stable self-signed code-signing certificate, `FlowLocal Dev`
   (`scripts/create_cert.sh`) — without this, macOS revokes the Accessibility grant
   on every rebuild.
10. Builds the app in release mode (`scripts/build_app.sh release`).
11. Installs `Oxygen Flow.app` to `/Applications`, enables launch-at-login, and opens
    it.
12. Opens System Settings → Privacy & Security → Accessibility for the user to flip on.

## If it fails partway, diagnose and retry

- **Command Line Tools dialog** — this is the only step that truly needs a human.
  Tell the user a system dialog opened, wait for them to finish it, then re-run
  `./make.sh`.
- **`vendor/whisper.cpp` empty or build fails immediately** — submodule wasn't
  fetched: `git submodule update --init --recursive`, then re-run `./make.sh`.
- **Ollama not reachable** — `brew services start ollama`, or run `ollama serve` in a
  terminal and re-run `./make.sh`.
- **Whisper model download fails partway** — `make.sh` writes to a `.part` file and
  only renames it on success, so re-running is safe and resumes cleanly (re-downloads
  if incomplete).
- **Code-signing identity missing** — check with
  `security find-identity -v -p codesigning | grep "FlowLocal Dev"`; if absent, run
  `scripts/create_cert.sh` directly.
- Re-running `./make.sh` after any fix is always safe — every step checks whether it's
  already done before doing it.

## Verify it worked

Headless check, no GUI or permissions needed:

```bash
.build/release/FlowLocal --selftest vendor/whisper.cpp/samples/jfk.wav
```

This runs the whisper.cpp → Ollama cleanup pipeline on a sample clip and prints
timing plus the cleaned transcript. If that prints a coherent transcript, the STT and
LLM cleanup pipeline both work correctly.

Then confirm the app itself launched: check for "Oxygen Flow" in the menu bar, or
`pgrep -f "Oxygen Flow"`.

## Rebuilding after source changes

```bash
scripts/build_app.sh release
open "Oxygen Flow.app"
```

No need to re-run all of `make.sh` — only the app binary needs rebuilding once
dependencies (Ollama, whisper model, cert) are already in place.
