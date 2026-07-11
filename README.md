# FlowLocal

A fully local clone of [Wispr Flow](https://wisprflow.ai) — AI voice dictation that works in
any app, running **100% offline** on your Mac. No login, no account, no cloud.

Press **Control+~**, speak, press **Control+~** again. Your speech is transcribed by
whisper.cpp, cleaned up (grammar, punctuation, filler removal, formatting) by a local Ollama
model, and pasted at your cursor — usually within a fraction of a second.

## Pipeline

```
Control+~ (toggle)             floating pill overlay
      │                              ▲
      ▼                              │ state
  AVAudioEngine ──16kHz mono──▶ whisper.cpp (Metal) ──raw text──▶ Ollama (streaming)
                                                                        │ cleaned text
                                                                        ▼
                                              paste at cursor (Cmd+V, progressive)
```

- **STT:** whisper.cpp (large-v3-turbo GGML) with Metal — kept warm in memory.
- **Cleanup:** Ollama `qwen2.5:3b-instruct` (default) via streaming `/api/generate`, pinned warm
  with `keep_alive: -1`. Text is injected progressively at sentence boundaries so long
  dictations appear as they generate.
- **App:** native Swift/SwiftUI menu-bar app (`NSPanel` pill, `CGEventTap` hotkey, `AVAudioEngine`,
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

# 2. Build and assemble the signed .app
./scripts/build_app.sh release

# 3. Launch
open FlowLocal.app
```

On first launch, grant:
- **Microphone** (prompted on first dictation).
- **Accessibility** — System Settings → Privacy & Security → Accessibility → enable FlowLocal.
  Required for the global hotkey and for pasting into other apps. Use the menu-bar item's
  "Grant Accessibility & Retry" if the hotkey isn't responding.

## Headless self-test

Verify the native pipeline without the GUI/permissions:

```bash
.build/release/FlowLocal --selftest vendor/whisper.cpp/samples/jfk.wav
```

## Settings (menu bar → Settings…)

- Whisper model path
- Ollama endpoint + model
- Cleanup on/off and formatting style (Formal / Casual / Very Casual)
- Launch at login

## Notes / known limitations

- Ad-hoc code signature: macOS may reset granted permissions after a rebuild (the signature
  hash changes). Grant again, or sign with a stable developer certificate to avoid this.
- Text injection uses Cmd+V (paste); works in nearly all apps. A keystroke-typing fallback for
  the rare app that ignores paste is not yet implemented.
- Phase 2 (not yet built): context-awareness (active app + nearby text), personal dictionary,
  voice/text shortcuts, whisper-mode gain tuning, dictation history.
