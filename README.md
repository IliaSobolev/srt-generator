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

## Build

```sh
./build-app.sh            # → dist/SRT Generator.app
open "dist/SRT Generator.app"
```

Requires Xcode 26+ and Apple Silicon.

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

```
SRTGenerator (app + CLI)   SwiftUI views, CLI, LiveDependencies (composition root),
        │                  TranslationBridge (Apple Translation), PanelFilePicker (AppKit)
        ▼
SRTEngines                 WhisperProvider (WhisperKit), ParakeetProvider (FluidAudio)
        │
        ▼
SRTCore                    AppState ─┬─ ModelManager   (downloads, one-click use)
(no third-party deps)                ├─ JobQueue       (decode → transcribe → write → translate)
                                     └─ TranscriptionService (loaded engine → subtitle cues)
                           Protocols: ModelProvider, SpeechEngine, AudioDecoding, Translating,
                                      SubtitleWriting, FilePicking, Sleeper
```

All dependencies are injected through `AppDependencies`. The app wires in the real implementations;
tests wire in fakes.

## Tests

```sh
swift test               # Swift Testing suite for SRTCore
scripts/coverage.sh      # coverage table; fails unless SRTCore line coverage is 100%
```

The `swift-test-writer` Claude Code subagent (`.claude/agents/swift-test-writer.md`) knows these conventions.
Ask Claude to "use swift-test-writer" after changing `SRTCore`.
