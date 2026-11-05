# SRT Generator

A native macOS 26+ app that turns any audio or video file into `.srt` subtitles, **fully on-device**.
Its interface uses the Liquid Glass design.

- **Speech recognition:** OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit), running on CoreML (Neural Engine/GPU).
  Supports 99 spoken languages with auto-detection. Each model downloads once to
  `~/Library/Application Support/SRTGenerator`; after that, transcription works offline.
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
    [--model tiny|base|small|626MB|turbo|large-v3] [--language auto|uk|de|…] [--english] [-o dir] files…
```

## Models

| Model | Size | Notes |
|---|---|---|
| Tiny / Base | 75–145 MB | fast, lower accuracy |
| Small | ~480 MB | good balance |
| **Large v3 Turbo (compact)** | ~630 MB | default; near-best accuracy |
| Large v3 Turbo | ~1.6 GB | |
| Large v3 | ~3 GB | most accurate, slowest |

The first time a model loads, CoreML compiles it for your Mac. This can take a few minutes. Later loads are fast.
