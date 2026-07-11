# Oxygen Flow

**A completely free, fully offline version of [Wispr Flow](https://wisprflow.ai).** AI voice
dictation that works in any app, running **100% on your Mac** — no login, no account, no cloud,
no subscription.

Press **Control+~**, speak, press **Control+~** again. Your speech is transcribed by
whisper.cpp, cleaned up (grammar, punctuation, filler removal, formatting) by a local model, and
pasted at your cursor — usually within a fraction of a second. If no text field is focused, the
result is placed on your clipboard instead.

> The Swift module/executable is still named `FlowLocal` internally (a mechanical rename to come);
> everything user-facing — the app, icon, window, menu bar — is **Oxygen Flow**.

## Install (one command)

Apple Silicon Mac. Clone and run the installer — it does **everything**:

```bash
git clone https://github.com/evangandy/Oxygen-Flow.git
cd Oxygen-Flow
./make.sh
```

`make.sh` installs the toolchain (Command Line Tools, Homebrew, cmake), installs & starts Ollama,
pulls the cleanup model, downloads the Whisper speech model, builds the app, installs it to
**/Applications**, enables it at login, and opens the one-time permission panes for you. It's safe
to re-run — finished steps are skipped.

First launch, grant the two permissions macOS requires of any dictation app:
- **Accessibility** — for the global hotkey and pasting into other apps (the installer opens this
  pane; flip on "Oxygen Flow").
- **Microphone** — you'll be asked the first time you dictate. Click Allow.

> The app is **self-signed** (no paid Apple Developer ID). Because you build it locally, there's no
> Gatekeeper "damaged app" warning. If you ever copy the built `.app` to another Mac, that Mac will
> need a one-time **right-click → Open**.

## Using it

- **Control+~** — start dictating; press again to stop. (Configurable in Settings.)
- The floating **chip** shows a live waveform with a **✕** (cancel) and **✓** (confirm) button, and
  appears on whichever monitor your mouse is on.
- **No editable field focused?** The text is copied to your clipboard — the chip shows
  "Copied · ⌘V".

## Features

- **Instant local dictation** — whisper.cpp (Metal) + Ollama, both kept warm in memory.
- **History & insights** — every dictation is saved locally (raw + cleaned text) so you can review
  what changed; tracks words/min, day streaks, time saved, activity, and where you dictate most.
- **Context-aware formatting** — code editors get concise/technical cleanup; Gmail/Mail get an
  email tone; everything else uses a generalist style.
- **Quiet / whisper speech** — adaptive input-gain normalization so faint speech is still picked up.
- **Customizable shortcut** — default Control+~; record your own in Settings.
- **Model picker** — choose any model installed in your local Ollama.
- **Auto-starts Ollama** — if it isn't running, the app launches it for you.
- **Private by design** — nothing ever leaves your machine.

## Pipeline

```
Control+~ (toggle)             floating chip (waveform + ✕ / ✓)
      │                              ▲
      ▼                              │ state
  AVAudioEngine ──16kHz mono──▶ whisper.cpp (Metal) ──raw text──▶ Ollama (streaming)
                                                                        │ cleaned text
                                                                        ▼
                                        paste at cursor (Cmd+V) — or copy to clipboard
```

- **STT:** whisper.cpp (large-v3-turbo GGML) with Metal — kept warm in memory.
- **Cleanup:** local Ollama `qwen2.5:3b-instruct` (default) via streaming `/api/generate`, pinned
  warm with `keep_alive: -1`. Text is injected progressively at sentence boundaries.
- **App:** native Swift/SwiftUI menu-bar app (`NSPanel` chip, `CGEventTap` hotkey, `AVAudioEngine`,
  `CGEvent` paste). The binary statically links whisper.cpp — no external dylibs.

Measured on an M4 Pro (JFK 11s clip): model load 0.78s (once), transcribe 0.62s, cleanup
first-token 0.22s, cleanup total 0.55s.

## Manual / developer build

`make.sh` chains these; run them individually while developing:

```bash
./scripts/build_whisper.sh     # build whisper.cpp static libs (once)
./scripts/make_icon.sh         # (optional) regenerate the app icon
./scripts/build_app.sh release # build + assemble the signed .app
open "Oxygen Flow.app"
```

Requirements for a manual build: Apple Silicon Mac (macOS 14+), Xcode **Command Line Tools**
(`swift`, `cmake`), [Ollama](https://ollama.com) running with `qwen2.5:3b-instruct` pulled, and a
whisper GGML model (set its path in Settings).

Headless pipeline check (no GUI/permissions):

```bash
.build/release/FlowLocal --selftest vendor/whisper.cpp/samples/jfk.wav
```

## Settings

Open the main window (menu bar → Open Dashboard) → **Settings**, or ⌘, :

- **Whisper model** path (the speech-to-text `.bin` file).
- **Cleanup (Ollama)** — enable/disable, pick any installed model, endpoint, formatting style, and
  "Adapt to active app" (code editors / Gmail).
- **Dictation shortcut** — record your own key combo (default Control+~).
- **Launch at login**, Accessibility status.
- **Privacy & history** — reveal the plain-text history in Finder, or clear it.

## Data & privacy

Every dictation is written to
`~/Library/Application Support/FlowLocal/history/transcriptions.json` as plain-text JSON —
**both** the raw transcript and the cleaned output — so you can audit exactly what the model
changed. Nothing is ever uploaded. Use Settings → Clear history (or delete the file) to wipe it.

## Insights

Fast stats (words/min, streaks, time saved, activity, top apps) are computed from your history.
Deeper *semantic* insights are designed to be built **incrementally**: because a full history can
exceed 100k words — more than a local model can read at once — each dictation gets a one-line AI
gist the moment it's saved, and those gists roll up into themes. Nothing is ever batched or
uploaded. (The gist field is scaffolded; the summarization pass is the next step.)

## Notes / limitations

- **Apple Silicon only.** The build is arm64; Intel Macs would need a universal rebuild of the
  whisper libraries.
- **Self-signed.** macOS may reset granted permissions after a rebuild (the signature hash
  changes). Re-grant if the hotkey stops responding.
- Text injection uses Cmd+V (paste); the clipboard fallback covers non-editable targets. A
  keystroke-typing fallback isn't implemented yet.
