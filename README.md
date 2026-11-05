# SRT Generator

A native macOS 26+ app that turns any audio or video file into `.srt` subtitles, **fully on-device**.
Its interface uses the Liquid Glass design.

- **Speech recognition:** the same model list as [HandyAI](https://github.com/JIEHT9U/HandyAI), using native CoreML builds:
  OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (99 languages), and NVIDIA Parakeet via
  [FluidAudio](https://github.com/FluidInference/FluidAudio). In **Settings → Models** (⌘,), one click downloads a model
  and makes it active. After that, transcription works offline.
- **Formats:** if `ffmpeg` is installed (`brew install ffmpeg`), any format it can read works (MKV, WebM, AVI, FLV, OGG, Opus, WMA, TS, …).
  Without ffmpeg, the app falls back to AVFoundation (MP4, MOV, M4A, MP3, WAV, AIFF, CAF, …).
- **Output languages:**
  - Original spoken language → `name.srt`
  - Whisper's built-in translation to English → `name.en.srt`
  - Any number of extra languages via Apple's on-device Translation framework → `name.<lang>.srt`
- Supports drag & drop, folders, batch queue, preview, and "Show in Finder". Existing `.srt` files are never overwritten.

## Download

Get the latest `SRTGenerator-X.Y.Z.dmg` from the [Releases page](../../releases/latest).
**Requires macOS 26 (Tahoe) or later on Apple Silicon.** Models aren't bundled; you download them in the app.

**Verify the download** (optional): put the `.sha256` file next to the DMG and run

```sh
shasum -a 256 -c SRTGenerator-X.Y.Z.dmg.sha256   # prints "SRTGenerator-X.Y.Z.dmg: OK"
```

**First launch (unsigned build).** Releases are not signed with an Apple Developer ID or notarized, so macOS
Gatekeeper blocks the first launch ("Apple could not verify…"):

1. Open the DMG and drag **SRT Generator** to **Applications**.
2. Open the app once. When macOS blocks it, open **System Settings → Privacy & Security**, scroll to the message
   about SRT Generator, and click **Open Anyway**, then confirm.
3. Alternatively, in Terminal: `xattr -dr com.apple.quarantine "/Applications/SRT Generator.app"`.

If you'd rather not trust a prebuilt binary, build it yourself (below). It takes about two minutes.

## Privacy

All transcription and translation happens **on your Mac**. Your video, audio, transcripts and subtitles never leave
the device. The app has no backend, no accounts, no telemetry, no analytics, no crash reporting and no update checks.

The only network traffic is downloading a speech model, and only when you click it in Settings → Models:

| Host | Why |
|---|---|
| `huggingface.co` | Model files (WhisperKit / FluidAudio) and the Whisper tokenizer, fetched once on first use of a Whisper model |
| `*.hf.co` (e.g. `us.aws.cdn.hf.co`) | Hugging Face's CDN, which serves the model weights |

Hugging Face sees your IP address and which model you download, as with any download. Apple's Translation
framework (for extra subtitle languages) downloads its language packs through macOS itself; the translation runs
on-device. After a model is downloaded, the app works fully offline.

This policy is enforced in CI (`scripts/check-network-policy.sh`); see
[docs/adr/0002-network-policy.md](docs/adr/0002-network-policy.md).

## Build from source

```sh
git clone <this repo> && cd srtgenerator
make app                  # → dist/SRT Generator.app (or ./build-app.sh)
open "dist/SRT Generator.app"
make dmg                  # optional: dist/SRTGenerator-<version>.dmg + .sha256
```

Requires Xcode 26+ and Apple Silicon. Contributors: see [CONTRIBUTING.md](CONTRIBUTING.md).

## CLI

```sh
"dist/SRT Generator.app/Contents/MacOS/SRTGenerator" --cli \
    [--model small|medium|turbo|large|parakeet-tdt-0.6b-v2|parakeet-tdt-0.6b-v3] \
    [--language auto|uk|de|…] [--english] [-o dir] files…
```

## Models

| Model | Engine | Download | Languages | Notes |
|---|---|---|---|---|
| Whisper Small (default) | Whisper | 486 MB | 99 | Fast and fairly accurate |
| Whisper Medium | Whisper | 1.5 GB | 99 | Good accuracy, medium speed |
| Whisper Turbo | Whisper | 1.6 GB | 99 | Balanced accuracy and speed |
| Whisper Large | Whisper | 948 MB | 99 | Good accuracy, but slow (quantized large-v3) |
| Parakeet V2 | Parakeet | ~470 MB | English | Best for English |
| Parakeet V3 | Parakeet | ~480 MB | 25 European | Fast and accurate |

Whisper models are stored in `~/Library/Application Support/SRTGenerator`, Parakeet models in
`~/Library/Application Support/FluidAudio`. The first time a model loads, CoreML compiles it for your Mac.

## Settings

- **Model Settings:** spoken language, translate to English (Whisper only), custom words (Whisper prompt),
  Neural Engine or GPU, unload the model after an idle time, and Whisper options (VAD, temperature fallback,
  non-speech suppression).
- **Subtitles:** max characters per line, max cue duration, and output folder.

## Architecture

SwiftPM package with three modules (`SRTCore` logic, `SRTEngines` adapters, `SRTGenerator` app and composition
root), MVVM, and dependency injection through protocols. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the
decision records in [docs/adr](docs/adr).

## Development

```sh
make ci          # lint, build (warnings = errors), tests + 100% SRTCore coverage gate, network policy
make test        # unit + architecture tests
make mutate      # mutation testing (slow, on demand)
```

Agents: `CLAUDE.md` holds the project rules for Claude Code. `.claude/agents/` has `swift-test-writer` (tests and
coverage) and `reviewer` (read-only review).

## License

[MIT](LICENSE)
