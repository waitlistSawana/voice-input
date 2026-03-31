# VoiceInput

English | [中文](./README_CN.md)

An experimental macOS menu-bar voice input app for fast hold-to-talk dictation.

`VoiceInput` lets you hold `Fn` to record, release to inject text into the currently focused input field, and optionally run a conservative LLM refinement pass before pasting. It is built for macOS 14+, defaults to Simplified Chinese, and is designed around a lightweight menu-bar workflow instead of a full Dock app.

> Status: experimental, but structured like a shippable repo. Core flows are implemented, packaging works, and the current rough edges are documented below.

## Highlights

- `Fn` hold-to-talk interaction with global key monitoring
- Streaming transcription via Apple Speech Recognition
- Default locale set to `zh-CN`, with menu-bar switching for English, Simplified Chinese, Traditional Chinese, Japanese, and Korean
- Bottom-centered HUD built with `NSPanel` and `NSVisualEffectView`
- Real-time audio metering pipeline for waveform-driven feedback
- Clipboard-based text injection with temporary ASCII input-source switching for CJK IMEs
- Optional OpenAI-compatible LLM refinement for conservative transcript correction
- `LSUIElement` app packaging with Swift Package Manager and a `Makefile`

## Why This Exists

This repository started as an experiment inspired by [yetone/voice-input-src](https://github.com/yetone/voice-input-src), where the source repo is essentially the prompt. I used that idea as a starting point, then ran the prompt through a Codex workflow augmented with [obra/superpowers](https://github.com/obra/superpowers) and iterated it into a real Swift codebase with tests, packaging, and documentation.

So this repo is not just a prompt archive. It is the actual implementation produced from that experiment, kept in a state that can be built, inspected, tested, and shipped forward.

## What It Does

When you hold `Fn`, `VoiceInput` starts recording through `AVAudioEngine` and streams audio into Apple's speech recognizer. While speaking, a bottom HUD shows live transcript updates and waveform feedback. When you release `Fn`, the session finalizes the transcript, optionally sends it through a conservative LLM refinement pass, then injects the final text into the currently focused input field by pasting through the clipboard.

To avoid CJK input methods swallowing `Cmd+V`, the app can temporarily switch to an ASCII input source before injection and restore the original input source afterward.

## Quick Start

Requirements:

- macOS 14+
- Xcode command line tools
- Accessibility permission
- Microphone permission
- Speech Recognition permission

Build the app bundle:

```bash
make build
```

Run it locally:

```bash
make run
```

Install it into `/Applications`:

```bash
make install
```

Clean local build artifacts:

```bash
make clean
```

The generated app bundle is:

```text
dist/VoiceInput.app
```

## Permissions

`VoiceInput` needs three macOS permissions to work correctly:

- `Accessibility`: required for global `Fn` monitoring, simulated paste, and input-source switching
- `Microphone`: required for audio capture
- `Speech Recognition`: required for Apple speech transcription

The current implementation assumes the user manually grants these permissions when prompted or through System Settings.

## LLM Refinement

LLM refinement is optional and disabled unless configured.

The menu-bar app exposes a `LLM Refinement` submenu with:

- an enable or disable toggle
- a `Settings...` window
- fields for `API Base URL`, `API Key`, and `Model`
- a connection test action

The refinement prompt is intentionally conservative. The model is expected to fix only obvious recognition mistakes, especially mixed Chinese-English technical terms such as `配森` to `Python` or `杰森` to `JSON`, while leaving correct text unchanged.

## Project Structure

```text
Sources/AppMain   App entry point and lifecycle wiring
Sources/Core      Speech, hotkey, injection, settings, permissions, LLM logic
Sources/UI        Menu-bar UI, floating HUD, settings window
Resources         Info.plist, entitlements, app icon assets
Tests             Core, UI, and smoke tests
docs              Specs, plans, and manual test notes
```

## Current Gaps

This repo is functional, but it is not pretending to be finished. Based on current manual testing:

- HUD waveform rendering still has visual issues in real use and needs a proper recorded pass for UI verification
- after quitting from the menu bar, the system `Fn` long-press behavior may not restore cleanly
- light or quiet speech is currently less reliable than stronger input
- there is no polished release pipeline yet, only local app-bundle packaging via `make`

These are active product-quality gaps, not hidden footnotes.

## Verification

The repo includes automated coverage for the core state machines and packaging flow, plus manual test checklists:

- [English manual checklist](./docs/manual-test-checklist.md)
- [Chinese manual checklist](./docs/manual-test-checklist.zh-CN.md)

Typical verification commands:

```bash
swift test
make build
```

## Inspiration

- [yetone/voice-input-src](https://github.com/yetone/voice-input-src)
- [obra/superpowers](https://github.com/obra/superpowers)

## License

No license file has been added yet.
