# Oxygen Flow

**A completely free, fully offline version of [Wispr Flow](https://wisprflow.ai).** AI voice
dictation that works in any app, running **100% on your Mac** — no login, no account, no cloud,
no subscription, nothing ever leaves your machine.

Press **Control+~**, speak, press **Control+~** again. Your speech is transcribed locally,
cleaned up (grammar, punctuation, filler removal, formatting), and pasted at your cursor.

## Setup

**Requirement: Apple Silicon Mac (M1 or later), macOS 14+.**

### If you have Claude Code (or a similar coding agent)

Clone the repo, then paste this to your agent:

> Set up Oxygen Flow on this Mac: run `./make.sh` to install everything (toolchain, Ollama, the
> speech model, and the app itself), and if anything in it fails, fix it and re-run until it
> finishes cleanly. Confirm the code-signing certificate got created (`security find-identity -v
> | grep "FlowLocal Dev"`) — that's what keeps macOS from revoking the Accessibility permission
> on every rebuild — and run `scripts/create_cert.sh` if it's missing. Then open the app and
> confirm it launches.

```bash
git clone --recurse-submodules https://github.com/evangandy/Oxygen-Flow.git
cd Oxygen-Flow
```

That's it — hand the rest to your agent. It can keep iterating on the app afterward too (rebuild,
tweak settings, restart it) without you typing commands yourself.

### Doing it yourself, no agent

```bash
git clone --recurse-submodules https://github.com/evangandy/Oxygen-Flow.git
cd Oxygen-Flow
./make.sh
```

`make.sh` does **everything**: installs the toolchain (Command Line Tools, Homebrew, cmake),
installs & starts Ollama, pulls the cleanup model, downloads the Whisper speech model, creates a
stable local code-signing certificate, builds the app, installs it to **/Applications**, enables
it at login, and opens the permissions pane for you. Safe to re-run — it skips finished steps.

### Permissions (macOS asks once)

- **Accessibility** — for the global hotkey and pasting into other apps. `make.sh` opens this pane
  for you; flip on "Oxygen Flow".
- **Microphone** — you'll be asked the first time you dictate. Click Allow.

> The app is self-signed with a certificate generated on your own machine (no paid Apple Developer
> ID needed) — that's normal, and how it avoids Gatekeeper's "damaged app" warning without one.

## Using it

- **Control+~** — start dictating; press again to stop. (Change it in Settings.)
- **Control+Command+R** — select text in any app, press this, and it gets rewritten in place by
  the local model. Separate from dictation — this one's allowed to actually rephrase.
- The floating chip shows a live waveform with **✕** (cancel) / **✓** (confirm), and follows
  whichever monitor your mouse is on.
- **No editable field focused?** The result goes to your clipboard instead — the chip shows
  "Copied · ⌘V".
- **Voice commands while dictating** — say "scratch that" to undo the last sentence, "new
  paragraph"/"new line" to break, or "comma"/"period"/"question mark" etc. for literal punctuation.
- **Dictionary** (sidebar) — teach it names, acronyms, or jargon it should recognize exactly (e.g.
  "10-K") and, optionally, what they mean, so cleanup understands the term instead of guessing.
- **Snippets** (sidebar) — say a trigger phrase as your whole dictation and it pastes a canned
  block instead (a signature, an address, boilerplate you say often).
- **Settings** — Whisper model, language (100+, or auto-detect), cleanup style (Formal / Casual /
  Very Casual / Notes), per-app style overrides, personal tone (paste writing samples to match
  your voice), auto-submit, and privacy mode (skip saving history entirely).

## If setup breaks

Point your agent at the failure — it's meant to be able to fix its own setup. A few common ones:

- **`vendor/whisper.cpp` is empty / build fails immediately** — the git submodule wasn't fetched.
  Run `git submodule update --init --recursive`, or just re-run `./make.sh` (it self-heals this).
- **Hotkey stops responding after a rebuild** — the code-signing identity changed. Run
  `scripts/create_cert.sh` once (if you haven't), then rebuild with `scripts/build_app.sh release`
  and re-grant Accessibility.
- **Ollama not reachable** — `brew services start ollama`, or `ollama serve` in a terminal.

## Rebuilding after changes

```bash
scripts/build_app.sh release   # rebuild the app
open "Oxygen Flow.app"
```

Or tell your agent: "rebuild and relaunch Oxygen Flow." Headless pipeline check (no GUI/permissions
needed):

```bash
.build/release/FlowLocal --selftest vendor/whisper.cpp/samples/jfk.wav
```

## Data & privacy

Every dictation is written to
`~/Library/Application Support/FlowLocal/history/transcriptions.json` as plain-text JSON — both
the raw transcript and the cleaned output, so you can audit exactly what the model changed.
Nothing is ever uploaded, ever. Turn this off entirely in Settings → Privacy & history, or clear
it any time.

## Under the hood

```
Control+~ (toggle)             floating chip (waveform + ✕ / ✓)
      │                              ▲
      ▼                              │ state
  AVAudioEngine ──16kHz mono──▶ whisper.cpp (Metal) ──raw text──▶ Ollama
                                                                        │ cleaned text
                                                                        ▼
                                        paste at cursor (Cmd+V) — or copy to clipboard
```

- **STT:** whisper.cpp (large-v3-turbo GGML) with Metal, kept warm in memory. The personal
  dictionary biases decoding toward exact spelling via whisper's `initial_prompt`.
- **Cleanup:** local Ollama (`qwen2.5:3b-instruct` by default) via `/api/generate`, pinned warm
  with `keep_alive: -1`. A minimal-edit prompt strips filler/fixes grammar without rephrasing;
  the separate "rewrite selection" command uses a more liberal prompt that's allowed to restructure.
- **App:** native Swift/SwiftUI menu-bar app (`NSPanel` chip, `CGEventTap` hotkey, `AVAudioEngine`,
  `CGEvent` paste/copy). Statically links whisper.cpp — no external dylibs at runtime.
- **Everything else** (history, insights, settings, dictionary, snippets) is plain SwiftUI reading
  local JSON files under `~/Library/Application Support/FlowLocal/`.

Measured on an M4 Pro (JFK 11s clip): model load 0.78s (once), transcribe 0.62s, cleanup
first-token 0.22s, cleanup total 0.55s.

## Notes / limitations

- **Apple Silicon only.** The build is arm64; an Intel Mac would need a universal rebuild of the
  whisper libraries.
- **Mac-only.** No Windows/iPhone/Android — this is a native macOS app, not a cross-platform one.
- Self-signed apps can lose the Accessibility grant if the signing identity changes — the stable
  `FlowLocal Dev` certificate (`scripts/create_cert.sh`) is what prevents that across rebuilds.
