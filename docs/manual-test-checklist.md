# Manual Test Checklist

- Grant `Microphone`, `Speech Recognition`, and `Accessibility` permissions on first launch, then relaunch and confirm the app handles both granted and denied states correctly.
- Hold `Fn` and speak, and confirm recording only starts while the key is held and stops immediately on release.
- Hold `Fn` inside a text field and confirm the system emoji picker does not appear.
- Speak softly and loudly in separate runs and confirm the live HUD waveform clearly responds to the difference in input level.
- Confirm the HUD stays bottom-centered while partial transcript text updates, and that it resizes smoothly as the text grows.
- When the HUD is already visible, trigger an equivalent `show()` activation again and confirm it does not flicker or replay the enter animation.
- During longer dictation with frequent partial transcript updates, confirm width changes stay smooth and do not restart animations repeatedly into a rubber-band effect.
- Open the language menu, switch across all supported languages, and confirm the active recognition locale updates with the selection.
- Open Settings, save a valid LLM API configuration, and use the connection test flow to verify the configuration works.
- Enable LLM refinement and confirm the success path injects the refined text instead of the raw transcript.
- Force an LLM failure and confirm the app falls back to the original transcript rather than aborting the flow.
- Trigger paste while a CJK input method is active and confirm the app restores the original input source after injection.
- Confirm the original clipboard contents are restored after text injection completes.
- Run `make build`, launch the generated `.app` bundle, and repeat the core end-to-end voice input checks.
- Run `make run` and confirm the app launches correctly through the project workflow.
- Run `make install`, launch the installed app from `/Applications`, and repeat the end-to-end checks.
