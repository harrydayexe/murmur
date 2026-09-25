# AGENTS.md

Murmur is a macOS menu bar app. It records voice notes, transcribes them on-device, and saves them as Markdown in per-project folders, which are often Obsidian vaults.

**`SPEC.md` is the source of truth.** Read it before starting any work. If something you need isn't in the spec, or you have to diverge from it, update `SPEC.md` in the same change and say why.

## Non-negotiables
- **On-device only.** Use Apple `Speech` (SpeechAnalyzer) for transcription and `SystemLanguageModel` for text. No cloud or third-party models, no `URLSession`/`Network`, no network entitlement, no analytics.
- **Never lose a recording.** Write the audio and the raw transcript to disk before any AI step.
- **The user owns the front matter.** Never add a key the user's template didn't ask for. Only generate AI values that a template or setting actually uses.
- **Stay faithful to what was said.** Tidying may fix punctuation and remove fillers, and nothing more. Keep the fidelity guard.
- **Dependencies:** Apple frameworks, `KeyboardShortcuts` and `Yams` only. Ask before adding anything else.

## Stack
Swift 6 (strict concurrency), SwiftUI `MenuBarExtra`, macOS 26.4+, Apple silicon, App Sandbox on. The project is generated from `project.yml` with XcodeGen. Don't commit `.xcodeproj`.

## Commands
```sh
xcodegen generate
xcodebuild -scheme Murmur -destination 'platform=macOS' build
xcodebuild -scheme Murmur -destination 'platform=macOS' test
```
Run the tests before calling any task done. A change that breaks the build or tests isn't finished.

## How to work
- Build in the milestone order in SPEC §9, one milestone at a time. Each milestone should leave the app running.
- Put the template engine, front matter, chunker, fidelity guard and tag normaliser in **pure** code with no I/O and no model calls, and cover it with unit tests.
- Put speech, the model and folder access behind protocols (`Transcribing`, `TextPolishing`, `MetadataGenerating`, `FolderAccessing`) and test the pipeline with fakes. Foundation Models and the microphone aren't available in CI.
- UI state goes through the `@MainActor` `AppState`. File I/O stays off the main actor, and every write is atomic.
- Keep changes small and focused. Don't restructure code beyond what the task needs.

## Gotchas
- SpeechAnalyzer doesn't resample. Convert buffers to `bestAvailableAudioFormat`, and copy tap buffers before queueing them.
- Volatile results *replace* earlier volatile text. Only commit `isFinal` results. On stop, finish the input stream, then `finalizeAndFinishThroughEndOfInput()`, and don't cancel the results consumer.
- The on-device model's context is small. Read `contextSize`, use `tokenCount(for:)`, and create a new `LanguageModelSession` per chunk.
- `SystemLanguageModel` availability reasons have changed between OS point releases, so log them as strings.
- Obsidian properties need quoted wikilinks and `YYYY-MM-DDTHH:mm:ss` date-times.
- When the installed SDK disagrees with the spec or with WWDC sample code, trust the SDK and note the difference in `SPEC.md`.

## Can't verify here
Tell the user what needs a manual check rather than claiming it works: mic permission prompts, the live transcript, AI output quality, and how notes look in Obsidian.
