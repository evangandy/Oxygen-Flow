# Oxygen Flow

**A completely free, fully offline version of [Wispr Flow](https://wisprflow.ai).** AI voice
dictation that works in any app, running **100% on your Mac** — no login, no account, no cloud,
no subscription.

Press **Control+~**, speak, press **Control+~** again. Your speech is transcribed by
whisper.cpp, cleaned up (grammar, punctuation, filler removal, formatting) by a local Ollama
model, and pasted at your cursor — usually within a fraction of a second. If no text field is
focused, the result is placed on your clipboard instead, ready to paste.

> The Swift package/module and executable are still named `FlowLocal` internally (renaming the
> SwiftPM target is a mechanical follow-up); everything user-facing — the app, icon, window, and
> menu bar — is **Oxygen Flow**.

## Features

- **Instant local dictation** — whisper.cpp (Metal) + Ollama, both kept warm in memory.
- **Works everywhere** — pastes at your cursor via `Cmd+V`; falls back to the clipboard when
  there's no editable field focused.
- **Multi-monitor aware** — the floating chip appears on whichever screen your mouse is on.
- **Minimal chip** — just a live waveform with a cancel (✕) and confirm (✓) button. No transcript
  clutter.
- **History & insights** — every dictation is saved locally (raw + cleaned text) so you can review
  what changed. Tracks words/min, day streaks, time saved, activity, and where you dictate most.
- **Customizable shortcut** — default Control+~; record your own in Settings (e.g. ⌥Space).
- **Model picker** — choose any model installed in your local Ollama, right from Settings.
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
- **Cleanup:** any local Ollama model (default `qwen2.5:3b-instruct`) via streaming
  `/api/generate`, pinned warm with `keep_alive: -1`. Text is injected progressively at sentence
  boundaries so long dictations appear as they generate.
- **App:** native Swift/SwiftUI menu-bar app (`NSPanel` chip, `CGEventTap` hotkey, `AVAudioEngine`,
  `CGEvent` paste).

Measured on an M4 Pro (JFK 11s clip): model load 0.78s (once), transcribe 0.62s, cleanup
first-token 0.22s, cleanup total 0.55s.

## Requirements

- Apple Silicon Mac, macOS 14+.
- [Ollama](https://ollama.com) running (`ollama serve`) with a cleanup model pulled:
  `ollama pull qwen2.5:3b-instruct` (and optionally `qwen2.5:7b-instruct`).
- A whisper GGML model at `~/Desktop/WisprFlow/models/ggml-large-v3-turbo.bin`
  (or point to your own path in Settings).
- Xcode **Command Line Tools** (`swift`, `cmake`) — full Xcode not required.

## Build & run

```bash
# 1. Build whisper.cpp static libs (once)
./scripts/build_whisper.sh

# 2. (Optional) regenerate the app icon
./scripts/make_icon.sh

# 3. Build and assemble the signed .app
./scripts/build_app.sh release

# 4. Launch
open "Oxygen Flow.app"
```

On first launch, grant:
- **Microphone** (prompted on first dictation).
- **Accessibility** — System Settings → Privacy & Security → Accessibility → enable Oxygen Flow.
  Required for the global hotkey and for pasting into other apps. Use the menu-bar item's
  "Grant Accessibility & Retry" if the hotkey isn't responding.

## Headless self-test

Verify the native pipeline without the GUI/permissions:

```bash
.build/release/FlowLocal --selftest vendor/whisper.cpp/samples/jfk.wav
```

## Settings

Open the main window (menu bar → Open Dashboard) → **Settings**, or ⌘, :

- **Whisper model** path (the speech-to-text `.bin` file).
- **Cleanup (Ollama)** — enable/disable, pick any installed model, endpoint, formatting style.
- **Dictation shortcut** — record your own key combo (default Control+~).
- **Launch at login**, Accessibility status.
- **Privacy & history** — reveal the plain-text history in Finder, or clear it.

## Data & privacy

Every dictation is written to
`~/Library/Application Support/FlowLocal/history/transcriptions.json` as plain-text JSON,
including **both** the raw transcript and the cleaned output, so you can audit exactly what the
model changed. Nothing is ever uploaded. Delete the file (or use Settings → Clear history) to wipe
it.

## Insights

Fast stats (words/min, streaks, time saved, activity, top apps) are computed directly from your
history. Deeper *semantic* insights ("what you write about most," tone trends) are designed to be
built **incrementally**: because a full history can exceed 100k words — more than a local model can
read at once — each dictation gets a one-line AI gist the moment it's saved (a few hundred ms, in
the background), and those gists roll up into themes. Nothing is ever batched or uploaded. (The
gist field is scaffolded in the store; the summarization pass is the next step.)

## Notes / known limitations

- Ad-hoc / self-signed certificate: macOS may reset granted permissions after a rebuild (the
  signature hash changes). Grant again, or sign with a stable developer certificate to avoid this.
- Text injection uses Cmd+V (paste). A keystroke-typing fallback for the rare app that ignores
  paste is not yet implemented (the clipboard fallback covers non-editable targets).
- Phase 2 (partially landed): context-awareness, personal dictionary, voice/text shortcuts,
  rolling LLM insight summaries.
