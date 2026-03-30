# Voice Input Menu Bar Design

## Goal

Build a macOS 14+ menu-bar voice input utility in Swift that records while the user holds `Fn`, performs streaming speech recognition with Chinese enabled by default, optionally refines the transcript with an OpenAI-compatible LLM, and injects the final text into the currently focused input field via paste.

## Product Scope

The app runs as an `LSUIElement` menu-bar utility with no Dock icon. The only recording trigger in v1 is hold-to-talk on the `Fn` key. The app requires the user to grant Accessibility, Microphone, and Speech Recognition permissions on first run. When recording, it shows a bottom-centered floating HUD with a live waveform driven by microphone RMS levels and a live transcript. On key release, it finalizes the transcript, optionally runs conservative LLM refinement, then injects the text into the focused input field.

Out of scope for v1:

- Alternate triggers such as `Globe`, double-tap `Fn`, click-to-record, or custom shortcuts
- Cloud ASR backends replacing Apple Speech Recognition
- Dock presence, onboarding wizard flows, or multi-window app navigation
- Formal production signing and notarization for distribution

## Recommended Architecture

Use a single-process AppKit menu-bar application with clearly separated coordination, system integration, and UI components.

### Core Components

#### App Lifecycle

- `VoiceInputApp` / `AppDelegate`
  - Starts the status item
  - Checks and requests permissions
  - Creates and wires the shared controllers
  - Owns the Settings window controller

- `StatusBarController`
  - Renders the menu bar item
  - Builds the menu for language selection, LLM enablement, Settings, and Quit
  - Reflects current configuration state from `SettingsStore`

#### Input Triggering

- `HotkeyMonitor`
  - Installs a global `CGEventTap`
  - Observes `flagsChanged` events and tracks `Fn` key transitions
  - Suppresses the `Fn` event when it is part of the hold-to-talk flow so the system emoji picker is not triggered
  - Emits only two semantic events: `didPressFn` and `didReleaseFn`

#### Speech Session Pipeline

- `SpeechSessionController`
  - Owns the end-to-end lifecycle for one hold-to-talk session
  - Starts audio capture and streaming recognition on `Fn` press
  - Updates the HUD with partial transcripts and RMS levels
  - Stops recognition on `Fn` release
  - Decides whether to go directly to injection or enter refinement
  - Ensures only one session runs at a time

- `AudioCaptureEngine`
  - Wraps `AVAudioEngine`
  - Taps the input node and forwards audio buffers both to the speech recognizer request and the RMS meter

- `AudioLevelMeter`
  - Computes RMS from incoming `AVAudioPCMBuffer`
  - Normalizes the level into a stable display range
  - Applies smoothing with separate attack and release behavior

- `SpeechRecognizerService`
  - Creates an `SFSpeechRecognizer` from the currently selected locale
  - Feeds audio through `SFSpeechAudioBufferRecognitionRequest`
  - Streams partial transcript updates to the session controller
  - Finalizes the best transcription on stop

#### HUD UI

- `FloatingPanelController`
  - Owns a bottom-centered non-activating `NSPanel`
  - Updates visibility, transcript text, panel width, and enter/exit animation

- `WaveformView`
  - Displays five rounded bars using `CALayer`
  - Maps smoothed RMS into weighted bar heights
  - Adds bounded per-bar jitter for more organic motion

- `HUDContentView`
  - Hosts the waveform and transcript label inside an `NSVisualEffectView`
  - Maintains the pill layout and sizing constraints

#### Injection and Refinement

- `TextInjector`
  - Saves and restores the clipboard
  - Detects the current input source
  - Temporarily switches to an ASCII source when the current source is CJK
  - Simulates `Cmd+V`
  - Restores the original input source and clipboard

- `LLMRefiner`
  - Calls an OpenAI-compatible chat completions endpoint
  - Sends a conservative system prompt that only fixes obvious recognition mistakes
  - Returns the original text if refine is disabled, unavailable, or fails

#### Configuration

- `SettingsStore`
  - Persists language choice, LLM enablement, API Base URL, API Key, and Model in `UserDefaults`
  - Provides defaults, especially `zh-CN` as the first-run language

## Session State Machine

Keep the runtime state machine minimal to avoid overlap between keyboard monitoring, recognition, refinement, and injection.

States:

1. `idle`
2. `recording`
3. `refining`
4. `injecting`

Transitions:

- `idle -> recording` when `Fn` is pressed
- `recording -> refining` when `Fn` is released and LLM refinement is enabled with a complete configuration
- `recording -> injecting` when `Fn` is released and no refinement is needed
- `refining -> injecting` when the refine request returns
- `injecting -> idle` when paste and restoration steps finish
- Any failure path collapses back to `idle`

Concurrency rule:

- If the app is in `refining` or `injecting`, ignore new `Fn` presses until the current pipeline finishes

## Fn Hold-To-Talk Behavior

The only trigger in v1 is pressing and holding `Fn`.

### Detection

- Listen for global `flagsChanged` events through `CGEventTap`
- Compare the current flags to the previous flags to infer `Fn` down and `Fn` up transitions
- Consume matching `Fn` events so they do not continue through the normal system path

### Suppression Goal

Suppressing the `Fn` event is required to prevent the system emoji picker or Globe behavior from activating while the app is listening.

### Failure Handling

If the event tap is disabled by the system or Accessibility permission is missing:

- Keep the menu bar app running
- Surface the problem through the menu and the permission guidance flow
- Do not attempt partial voice workflow without the hotkey monitor

## Speech Recognition Design

### Language Defaults and Selection

Default recognition locale: `zh-CN`

Menu options:

- `en-US` labeled as `English`
- `zh-CN` labeled as `简体中文`
- `zh-TW` labeled as `繁体中文`
- `ja-JP` labeled as `日本語`
- `ko-KR` labeled as `한국어`

The selected locale is stored in `UserDefaults`. If no value is stored, the app must use `zh-CN`.

### Recognition Flow

On `Fn` press:

1. Create an `SFSpeechRecognizer` for the selected locale
2. Create an `SFSpeechAudioBufferRecognitionRequest`
3. Configure the request for partial results
4. Start `AVAudioEngine`
5. Feed microphone buffers to both the request and the RMS meter
6. Show the HUD immediately, even before the first partial result arrives

On `Fn` release:

1. Stop accepting new microphone audio
2. End the audio request
3. Wait for the final best recognition result or fall back to the latest partial
4. If the resulting text is empty, close the session without injection and show a short empty-result state

### Transcript Display Rules

HUD text states:

- On recording start: `请讲话`
- During recognition: latest partial transcript
- On no usable result: `未识别到内容`
- During LLM refine: `Refining...`
- On recoverable recognition error: a short message such as `语音识别不可用`

## Floating HUD Design

### Window and Material

Use an `NSPanel` configured as:

- `borderless`
- `nonactivatingPanel`
- full-size content view
- visible across Spaces and full-screen apps
- above normal app windows without stealing key focus

The panel content is an `NSVisualEffectView` with `.hudWindow` material. The visible container is a borderless pill with:

- Height `56`
- Corner radius `28`
- No title bar
- No traffic lights
- No activation on show

### Layout

- Left waveform area fixed at `44x32`
- Right transcript label width flexible
- Overall pill width clamped between `160` and `560`
- Width expands and contracts smoothly based on measured text width

### Waveform Behavior

The waveform must be driven by real microphone RMS values, not a canned animation.

Bar weights:

- `0.5`
- `0.8`
- `1.0`
- `0.75`
- `0.55`

Signal shaping:

- Smooth upward motion with attack coefficient aligned to the requested 40 percent behavior
- Smooth downward motion with release coefficient aligned to the requested 15 percent behavior
- Add bounded random jitter of plus or minus 4 percent per bar for organic variation
- Preserve a visible minimum bar height so silence still shows a low baseline
- Allow tall peaks so speaking clearly produces obvious motion

Implementation preference:

- Render each bar as a rounded `CALayer`
- Update at approximately 60 fps using a display-linked or timer-driven renderer

### HUD Animation

- Enter animation: spring-like scale and fade over `0.35s`
- Width changes: smooth transition over `0.25s`
- Exit animation: scale-down and fade over `0.22s`

## Text Injection Design

Text injection uses the clipboard plus simulated paste.

### Injection Transaction

1. Save the current clipboard contents in full
2. Read the current input source
3. If the current source is a CJK input method, switch temporarily to an ASCII input source
4. Write the final text to the clipboard
5. Simulate `Cmd+V` with `CGEvent`
6. Wait a short stabilization interval
7. Restore the original input source
8. Restore the original clipboard contents

### Input Source Rules

ASCII source preference:

1. `com.apple.keylayout.ABC`
2. Fallback to a US keyboard layout if ABC is unavailable

CJK detection should inspect source metadata rather than relying only on localized display names. The purpose is to avoid paste interception or composition-buffer insertion when the focused app currently uses a Chinese, Japanese, or Korean input method.

### Error Handling

If the input source cannot be switched:

- Still attempt injection if clipboard writing and simulated paste are possible
- Always try to restore the clipboard, even if paste fails

## LLM Refinement Design

### Menu and Settings

The menu bar UI includes an `LLM Refinement` submenu with:

- Enable/disable toggle
- `Settings...` entry

The Settings window includes:

- `API Base URL` text field
- `API Key` text field
- `Model` text field
- `Test` button
- `Save` button

The API Key field must allow being fully cleared. Save behavior must persist exactly what the user entered, including an empty string.

### When Refinement Runs

Run refinement only when all of the following are true:

- LLM refinement is enabled
- API Base URL is non-empty
- API Key is non-empty
- Model is non-empty
- Transcript is non-empty

If refinement is active:

- Keep the HUD visible after `Fn` release
- Replace the transcript display with `Refining...`
- Delay injection until the refine step finishes

If refinement fails for any reason:

- Log the failure
- Fall back to the original transcript
- Continue to injection

### API Contract

Use an OpenAI-compatible chat completions request shape to minimize configuration complexity in v1.

### Conservative System Prompt

The refinement prompt must explicitly instruct the model to:

- Correct only obvious speech recognition mistakes
- Preserve all content that already appears correct
- Never rewrite, summarize, embellish, or remove correct text
- Preserve code terms, technical names, and mixed-language content whenever they already look right
- Fix common transliteration mistakes such as `配森` to `Python` and `杰森` to `JSON` when the correction is clearly warranted
- Return only the final corrected text and nothing else

## Permissions and First-Run UX

Required permissions:

- Accessibility
- Microphone
- Speech Recognition

First-run behavior:

- Check all three permissions on launch
- Prompt for the requestable permissions through system APIs
- Explain Accessibility setup when user action in System Settings is required
- Keep the app usable as a menu bar utility even when permissions are incomplete, but disable recording until the required permissions are granted

There is no full onboarding flow in v1. A lightweight alert or small guidance window is sufficient.

## Build and Packaging

### Runtime Mode

Set `LSUIElement` to `true` so the app appears only in the menu bar and not in the Dock.

### SwiftPM Layout

Repository structure:

- `Package.swift`
- `Sources/AppMain/`
- `Sources/Core/`
- `Sources/UI/`
- `Resources/Info.plist`
- `Resources/App.entitlements`
- `Tests/`
- `Makefile`

### Make Targets

- `make build`
  - Build the executable with SwiftPM
  - Assemble a signed `.app` bundle under `dist/`

- `make run`
  - Launch the built app

- `make install`
  - Copy the signed `.app` bundle to a local install target such as `/Applications`

- `make clean`
  - Remove build and distribution artifacts

### Signing

Use ad-hoc signing in v1 so the resulting `.app` bundle is locally runnable without requiring production distribution credentials.

## Testing Strategy

### Automated Tests

Unit-test the deterministic logic:

- Settings persistence and default language selection
- LLM configuration validation
- LLM request payload construction
- RMS normalization and waveform height mapping
- Input source classification logic

### Manual Verification

Use a manual checklist for the system-coupled behaviors that are hard to automate reliably:

- Permission prompts and denied-permission states
- `Fn` press and release behavior
- Suppression of the emoji picker
- Live waveform responsiveness to voice volume
- Partial transcript updates while speaking
- ASCII input source switching before paste
- Clipboard restoration after injection
- LLM refine success and fallback behavior
- Menu language switching
- Settings save and API test flows

## Risks and Guardrails

- `CGEventTap` reliability depends on Accessibility permission and can be disabled by the system
- `SFSpeechRecognizer` behavior varies with locale availability and user network conditions
- Simulated paste depends on target app behavior and may not succeed uniformly in every sandboxed or privileged app
- Input source restoration must be treated as best-effort but attempted in all exit paths
- LLM refinement must never block the primary workflow permanently; fallback to raw transcript is mandatory

## Implementation Notes

Design principles for v1:

- Optimize for stable hold-to-talk behavior over feature breadth
- Keep global state minimal and route all session activity through one coordinator
- Prefer AppKit and Core Animation for the floating HUD because the windowing and animation constraints are explicit and system-level
- Preserve the user's clipboard and input source state as carefully as possible
