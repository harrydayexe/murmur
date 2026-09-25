# Murmur — Spec 

A macOS menu bar utility that records spoken thoughts, ideas and technical decisions, transcribes them **on-device**, lightly tidies them with Apple's **on-device** Foundation Models, and saves each one as a Markdown note in the folder of the project being worked on. That folder is often inside an Obsidian vault.

The notes are raw material for blog posts about building projects. The owner will read them later to reconstruct how a project evolved, so **accuracy to what was said matters more than polish.**

> Name: **Murmur** (formerly the working name *Voicelog*). Bundle ID `dev.harryday.murmur`.

**Changes since v3:** front matter is now **100% user-controlled** (§5.3):
- The app never adds a key by itself.
- AI-generated values (tags, summary, type) only appear where the user places them in the template.
- Values nobody uses aren't generated at all.
- Note types, date formats, tag rules and the timeline file's front matter are all configurable.

---

## 1. Hard constraints

1. **Everything stays on the Mac.** Speech-to-text uses Apple's Speech framework and text processing uses `SystemLanguageModel` (the on-device model), and nothing else.
   - No cloud or third-party models of any kind: no Private Cloud Compute, Whisper, OpenAI, Anthropic, Google, and no third-party `LanguageModel` implementations. No analytics, crash reporters or update checkers.
   - The app has **no network entitlement** and doesn't import `URLSession`/`Network`; a test enforces this. The only network activity is macOS downloading Apple's speech model the first time (`AssetInventory`).
2. **Never lose a recording.** Save the audio and the raw transcript to disk *before* any AI step.
3. **Stay close to the speaker's words.** The model may fix punctuation, drop filler words and split paragraphs. It must not paraphrase, summarise the body, reorder, or add content. AI-generated parts are clearly labelled, and the raw transcript is always kept.
4. **The user owns the front matter.** Every key in a note's front matter comes from a template the user controls. The app never adds, renames, reorders or fills in keys on its own. AI output reaches front matter **only** through a placeholder the user wrote into a template.
5. **Dependencies:** Apple frameworks, plus `KeyboardShortcuts` (sindresorhus) and `Yams`, both via SPM. Nothing else.

## 2. Platform & tooling

| Item | Decision |
|---|---|
| OS minimum | **macOS 26.4** (for `SystemLanguageModel.contextSize` and `tokenCount(for:)`). Also runs on macOS 27. |
| Hardware | Apple silicon. Apple Intelligence must be on for the AI steps. Speech-to-text works without it. |
| Language | Swift 6 (strict concurrency), SwiftUI, with AppKit only where needed |
| Frameworks | `Speech`, `AVFoundation`, `FoundationModels`, `SwiftUI`, `ServiceManagement`, `UserNotifications` |
| Project | **XcodeGen** (`project.yml`), built with `xcodebuild`. The generated `.xcodeproj` is gitignored. |
| App type | `LSUIElement = YES`, using `MenuBarExtra` with `.menuBarExtraStyle(.window)` |
| Sandbox | **On**, with no `network.client` entitlement, so macOS itself blocks network access. Project folders are accessed through security-scoped bookmarks. |
| Entitlements | `com.apple.security.app-sandbox`, `com.apple.security.device.audio-input`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope` |
| Info.plist | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `LSUIElement` |
| Signing | Personal use: sign locally or with Developer ID, with Hardened Runtime on |

## 3. User experience

### 3.1 Menu bar icon
- Idle: `waveform`
- Recording: `record.circle.fill` in red, with the elapsed time
- Processing: `ellipsis.circle`
- Needs attention: `exclamationmark.triangle`

### 3.2 Popover (about 360pt wide)

**Idle**
- **Project** picker: each project's name, with its folder as secondary text and an Obsidian badge if the style is `obsidian`. The **active project** stays selected and the hotkey records into it. The last item, "New project…", opens the new-project sheet.
- **Note type** picker: `Auto` plus the user's **note type list** (§4.4). The picker is hidden if the list is empty.
- **Record** button with a hint for the hotkey (default `⌃⌥Space`)
- **Recent notes** (last 5 in the active project): click to open, ⌘-click to reveal in Finder, with **Open in Obsidian** for Obsidian-style projects
- Footer: status line, Settings… (⌘,), Quit

**Recording**: the project is locked while recording. Shows a timer, level meter, and live transcript (finalized text in primary colour, volatile tail in secondary). **Stop & Save** (hotkey or ⏎). **Discard** (Esc) asks for confirmation if the recording is longer than 10 s.

**Processing**: shows the current step ("Finishing transcription…", "Tidying (2/4)…", "Writing note…") and keeps going if the popover closes.

**Done**: "Saved to *Project*: *Title*" with **Open** and **Reveal** buttons, plus an optional notification.

### 3.3 Global hotkeys
- Toggle recording
- Discard current recording (optional)
- Cycle active project (optional)

### 3.4 First run
1. Welcome screen.
2. Create the first project: name, folder (saved as a security-scoped bookmark), and automatic vault detection (§5.4).
3. **Pick a front matter preset** (§5.3): *None*, *Minimal*, or *Obsidian basic*. A preview is shown, and the default is *Minimal*. None of the presets include tags.
4. Request microphone permission, then speech recognition permission.
5. Install speech assets for the locale with `AssetInventory`, showing progress.
6. Check `SystemLanguageModel.default.availability`. If it's unavailable, explain why and make clear that notes will be saved without AI tidying.

## 4. Settings

### 4.1 Settings file
All settings live in one human-readable JSON file:
`~/Library/Containers/<bundle-id>/Data/Library/Application Support/Murmur/settings.json`
- A `SettingsStore` (`@MainActor @Observable`) loads it at launch and saves it atomically with a debounce of about 500 ms. It has a `"version": 1` field and keeps unknown keys when saving.
- If the file is corrupt, back it up as `settings.corrupt-<timestamp>.json`, load defaults, and show a warning.
- Settings → Advanced has a **Reveal settings file** button. Editing the file by hand requires a restart.

```json
{
  "version": 1,
  "activeProjectID": "8C1E…",
  "frontMatter": {
    "template": "created: {{datetime}}\nproject: {{project}}",
    "omitEmpty": true,
    "mergeLists": ["tags", "aliases"]
  },
  "noteTypes": ["idea", "decision", "thought", "problem", "progress"],
  "projects": [
    {
      "id": "8C1E…",
      "name": "Murmur",
      "folderBookmark": "<base64>",
      "folderPathHint": "/Users/harry/Vault/Projects/Murmur/Log",
      "style": "obsidian",
      "vaultRootPathHint": "/Users/harry/Vault",
      "frontMatter": { "mode": "override", "template": "…", "timelineTemplate": "" },
      "glossary": ["SwiftUI", "swift ui => SwiftUI"],
      "defaultNoteType": null,
      "archived": false
    }
  ],
  "recording": { "locale": "en-GB", "keepAudio": true, "maxMinutes": 30, "inputDeviceUID": null },
  "ai": {
    "tidyLevel": "light",
    "title": true,
    "body": { "summary": true, "keyPoints": true },
    "classifyType": true,
    "tags": { "maxCount": 3, "mode": "free", "allowed": [], "prefix": "", "case": "lower", "separator": "-" },
    "glossary": ["Xcode"]
  },
  "output": { "filenamePattern": "{{date:YYYY-MM-DD}}-{{time:HHmm}}-{{title|slug}}", "writeTimeline": true, "notify": true },
  "launchAtLogin": false
}
```

### 4.2 Projects
Each project has its **own save folder**, front matter, note style and glossary.

`Project { id, name, folderBookmark, folderPathHint, style: standard|obsidian, vaultRootPathHint?, frontMatter: {mode: inherit|override|append, template, timelineTemplate}, glossary, defaultNoteType?, archived }`

**Settings → Projects tab** (a list with a detail pane):
- Add, remove (with confirmation; **files on disk are never deleted**), archive
- Detail fields: name, folder, note style (auto-detected, can be changed), default note type, glossary, front matter editor (§5.3)
- Folder status: ✅ writable / ⚠️ missing or no access, with a "Re-choose folder…" action

**Folder access rules**
- On launch, resolve all bookmarks and call `startAccessingSecurityScopedResource()`, keeping access open for the app's lifetime. If a bookmark is stale, re-create it.
- Two projects can share a folder; show a warning, but allow it.
- **Before recording**: if the active folder isn't writable, don't start. Show a fix action.
- **At save time**: if the folder has become unreachable, save to `Application Support/Murmur/Unsaved/<project>/`, show a notification, and offer **Move to project folder** later.

**Default folder**
- On first launch the settings file gets one project, **Inbox**, with no bookmark and `folderPathHint` = `~/Documents/Murmur` (the real home directory, not the sandbox container).
- The sandbox can't write there until the user grants access. When **Record** is pressed and the active project has no usable folder, an open panel appears at `~/Documents` ("Murmur saves notes to ~/Documents/Murmur — click Grant Access, or choose another folder"). If the user picks `~/Documents` itself, the app creates `Murmur/` inside it and bookmarks that subfolder. Any other choice is bookmarked as is. The prompt comes before recording rather than at save time, so a recording never finishes with nowhere to go. If the panel is cancelled, recording doesn't start.
- Settings → Projects has the same **Choose folder…** action.

### 4.3 Settings window tabs
- **General**: launch at login, notifications, hotkeys
- **Projects**: see §4.2
- **Recording**: input device, locale, keep audio, max length
- **Front matter**: global template editor, presets, omit-empty toggle, list-merge keys, **placeholder reference** (§5.3), and a **"Used AI values"** summary (§6.5)
- **Note types**: see §4.4
- **AI**: tidy level (`Off` / `Light`); AI title on/off; body summary and key points on/off; type classification on/off; **AI tags** rules (§5.3.5); global glossary; model status with a **Test** button
- **Advanced**: filename pattern (uses the same placeholder syntax), timeline on/off, Reveal settings file, Open logs folder

### 4.4 Note types
- An editable, ordered list of plain strings. Default: `idea, decision, thought, problem, progress`. Users can rename, add, remove and reorder them, or empty the list entirely.
- The popover picker shows `Auto` plus the list.
- If the user picks `Auto` and AI classification is on and the type is used somewhere (§6.5), the model chooses **only from this list** (dynamic schema with an `anyOf` over the list). Otherwise the type is empty.
- An empty type is omitted from the front matter when `omitEmpty` is on, and from the timeline line.

### 4.5 Glossary syntax
Global and per-project glossaries are combined:
- `SwiftUI` sets a preferred spelling, which is given to the model.
- `swift ui => SwiftUI` is a deterministic case-insensitive whole-word replacement, applied before the AI step.

## 5. Output

### 5.1 Folder layout (per project folder)
```
<project folder>/
  2026-09-25-1432-chose-sqlite-over-json.md
  timeline.md
  audio/
    2026-09-25-1432-chose-sqlite-over-json.m4a
```
- Filenames come from `output.filenamePattern`. After rendering, the name is cleaned: the characters `[ ] # ^ | \ / :` and control characters are removed, and it's capped at 100 characters. If the title is empty, `{{title|slug}}` falls back to `note`. Collisions get `-2`, `-3`, and so on.
- All writes are atomic: write a temp file in the same directory, then rename.

### 5.2 Note body
Each section can be switched off in the AI or Recording settings. Disabled or failed sections are left out, and there are never empty headings.
1. Front matter (§5.3). Left out entirely if the effective template is empty.
2. `# {{title}}`
3. Summary *(AI-generated)*, if `ai.body.summary` is on
4. Key points *(AI-generated)*, if `ai.body.keyPoints` is on
5. Audio embed/link, if audio is kept
6. `## Transcript` (tidied). If nothing was transcribed, it says *No speech was transcribed.* rather than leaving the heading empty.
7. Raw transcript (collapsed): the speech recogniser's output before glossary replacements and tidying. Left out if empty.

### 5.3 Front matter (fully user-defined)

#### 5.3.1 Principle
The front matter of a note is **exactly** the rendered template, and nothing else:
- The app adds **no** keys of its own. Title, date, project, type, tags and processing status are **not** written unless the user's template asks for them.
- AI values reach the front matter **only** through `{{ai_*}}` placeholders, or `{{type}}` when AI classification is on.
- If a value isn't used by any template, the body, the filename or the timeline, **it isn't generated** (§6.5).
- An empty effective template means **no front matter block** in the note.

#### 5.3.2 Where it's set
- **Global template:** Settings → Front matter
- **Project template**, with three modes:
  - `inherit` (default): use the global template
  - `override`: use only the project template
  - `append`: global template, then the project template. For duplicate top-level keys, the project value wins. Keys listed in `mergeLists` (default `tags`, `aliases`) are combined as lists without duplicates, global values first.
- **Timeline template** (per project, default empty): front matter for `timeline.md` when the app creates it.

**Presets** fill in the template, which the user can then edit freely:

| Preset | Template |
|---|---|
| None | *(empty)* |
| Minimal *(default)* | `created: {{datetime}}` |
| Obsidian basic | `title: {{title}}`<br>`created: {{datetime}}`<br>`project: "[[{{project}}]]"`<br>`audio: {{audio_link}}` |

**No preset uses `{{ai_tags}}`.** AI tags only appear if the user types that placeholder themselves.

#### 5.3.3 Placeholders

| Placeholder | Value | Source |
|---|---|---|
| `{{title}}` | AI title if `ai.title` is on, otherwise `Voice note {{time}}` | AI / app |
| `{{project}}` | Project name | app |
| `{{type}}` | Type picked by the user. If `Auto`: the AI-classified type if classification is on, otherwise empty | user / AI |
| `{{date}}`, `{{time}}`, `{{datetime}}`, `{{weekday}}` | Recording start. Default formats: `YYYY-MM-DD`, `HH:mm`, and `YYYY-MM-DDTHH:mm:ss` (obsidian) or ISO 8601 with offset (standard), `dddd` | app |
| `{{date:FORMAT}}` (also `time:`, `datetime:`) | Custom format using **Obsidian/moment-style tokens**: `YYYY YY MMMM MMM MM M DD D dddd ddd HH H hh h mm ss A Z ZZ w ww` (`w` is the ISO week number), with `[literal]` escapes | app |
| `{{duration}}` | `3m12s`. `{{duration_seconds}}` gives an integer | app |
| `{{locale}}` | `en-GB` | app |
| `{{filename}}` | Note filename without `.md` | app |
| `{{audio}}` / `{{audio_link}}` | Audio filename / style-appropriate link (`"[[x.m4a]]"` or `audio/x.m4a`). Empty if audio isn't kept. | app |
| `{{processing}}` | `tidied` / `tidied-partial` / `raw` | app |
| `{{app_version}}` | `0.4.0` | app |
| `{{ai_summary}}` | One-to-two sentence summary | **AI** |
| `{{ai_key_points}}` | List of key points | **AI** |
| `{{ai_tags}}` | List of tags, following the §5.3.5 rules | **AI** |

**Filters** can be chained: `{{title|lower}}`, `|upper`, `|slug`, `|wikilink` (wraps as `[[…]]`), `|quote`, `|flow` / `|block` (list layout), `|first` (first list item), `|default:"text"`.

Unknown placeholders are left as they are and flagged in the editor.

#### 5.3.4 Rendering rules (`TemplateRenderer` → `FrontMatterBuilder`)
1. Strip any leading or trailing `---` lines the user typed.
2. Substitute placeholders line by line:
   - **Whole scalar value** (`key: {{title}}`): output a YAML-safe scalar, quoted only when needed.
   - **Inside a double-quoted string** (`up: "[[{{project}}]]"`): escape `"` and `\`.
   - **Whole list value** (`tags: {{ai_tags}}`): a block list on the following lines (obsidian style) or a flow list `[a, b]` (standard style), unless `|flow` or `|block` is given.
   - **List item splice** (a line that is only `  - {{ai_tags}}`): expands into one `- item` line per element at the same indent, so users can mix fixed and AI tags:
     ```yaml
     tags:
       - voice-note
       - {{ai_tags}}
     ```
   - Anything else: insert literally, with newlines turned into spaces.
3. **`omitEmpty`** (default on): drop keys whose value renders empty (empty string, empty list, or a list whose items are all empty), and drop list-item lines that render empty.
4. If the mode is `append` and there are key collisions, merge structurally (parse both with `Yams`, apply the rules in §5.3.2, and emit with the app's YAML emitter: block lists in obsidian style, flow in standard, minimal quoting, wikilinks always quoted). **Otherwise, output the rendered text exactly as written**, so the user's key order, comments and formatting are kept.
5. Validate the result with `Yams`. If it fails, write the note **without front matter** and put the rendered block in a `%% front matter invalid: … %%` (obsidian) or `<!-- … -->` (standard) comment at the top of the body. Show a warning. Nothing is lost.

#### 5.3.5 AI tags (opt-in)
These rules only matter if a template uses `{{ai_tags}}`:
- `maxCount`: 0–10, default 3
- `mode`:
  - `free`: the model chooses any tags
  - `allowedOnly`: the model may **only** choose from the `allowed` list (dynamic schema `anyOf`). This is recommended for curated vaults, so the vault's tag list never grows unexpectedly.
- Normalising: the `case` setting (`lower` / `asIs`), spaces replaced with `separator` (`-` or `_`), `#` stripped, pure-number tags dropped, the optional `prefix` added (for example `topic/` for Obsidian nested tags), and duplicates removed.
- Settings shows a sample output and warns: "AI tags are only added where `{{ai_tags}}` appears in a template."

#### 5.3.6 Editor UX
- A monospaced `TextEditor` with placeholder syntax highlighting and autocompletion after `{{`
- An **Insert** menu listing every placeholder and filter, each with a description
- A **live preview** that renders the template against a sample note, with a switch between "with AI values" and "AI unavailable" samples, plus the parse status from `Yams` (✅, or an error with its line number)
- Presets menu (applying one asks for confirmation before replacing text)

### 5.4 Note style: `standard` vs `obsidian`
**Auto-detection:** when a folder is chosen, walk up its parent folders looking for a `.obsidian/` directory. If one is found, set `style = obsidian` and store `vaultRootPathHint`. The user can change the style.

The style affects the **body** markup and the **default formats** of placeholders. It never adds front matter keys.

| Element | standard | obsidian |
|---|---|---|
| Summary | `> **Summary** *(AI-generated)*: …` | `> [!summary] Summary (AI-generated)` callout |
| Key points | bold label + bullets | `> [!note]- Key points (AI-generated)` callout |
| Audio in body | `[Audio](audio/<file>.m4a)` | `![[<file>.m4a]]` |
| Raw transcript | `<details>` block | `> [!quote]- Raw transcript` collapsed callout, every line starting with `> ` |
| Invalid front matter comment | `<!-- … -->` | `%% … %%` |
| Timeline links | `[Title](file.md)` | `[[file\|Title]]` |
| Default `{{datetime}}` | ISO 8601 with offset | `YYYY-MM-DDTHH:mm:ss` |
| Default list layout | flow | block |
| `{{audio_link}}` | `audio/<file>.m4a` | `"[[<file>.m4a]]"` |

**Open in Obsidian:** `obsidian://open?path=<percent-encoded absolute path>` via `NSWorkspace` (a local URL scheme, not a network call).

### 5.5 Project timeline
Append one line per note to `<project folder>/timeline.md`. When creating the file, render the project's **timeline template** as its front matter (none if empty), then a `# <project> timeline` heading.
```markdown
- 2026-09-25 14:32 · **decision** · [[2026-09-25-1432-chose-sqlite-over-json|Chose SQLite over JSON for the cache]] — Decided to move the local cache…
```
The type and summary parts are left out when empty or disabled.

## 6. Processing pipeline

```
Record ─► Transcribe (live) ─► Finalize ─► Raw draft to disk ─► Tidy ─► Metadata ─► Final write ─► Timeline
                                           (crash-safe)         (optional) (only needed fields)
```
Take a snapshot of the project, style, templates and AI settings **when recording starts**.

### 6.1 Audio capture — `AudioRecorder`
- `AVAudioEngine` tap on `inputNode`. Read the input format at runtime; don't hard-code it.
- For each buffer:
  1. **Copy** it.
  2. Write it to `.m4a` (AAC, mono, 48 kbps) if Keep audio is on. Otherwise write to a temp CAF file.
  3. Convert (`AVAudioConverter`, `primeMethod = .none`) and yield `AnalyzerInput(buffer:)` into an `AsyncStream`.
  4. Publish the RMS level at about 20 Hz.
- Handle `AVAudioEngineConfigurationChange` by restarting the tap.

### 6.2 Transcription — `Transcriber`
- `SpeechTranscriber(locale:transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])`. If it isn't available, fall back to `DictationTranscriber`.
- `SpeechAnalyzer(modules:options: .init(priority: .userInitiated, modelRetention: .lingering))`. Call `bestAvailableAudioFormat(compatibleWith:)` and `prepareToAnalyze(in:)` when the popover opens.
- Three tasks: the producer, `analyzer.start(inputSequence:)`, and a consumer of `transcriber.results`. Keep finalized segments plus a **replaceable** volatile tail.
- **Stop order:**
  1. Stop the engine and remove the tap.
  2. `continuation.finish()`
  3. `await analyzer.finalizeAndFinishThroughEndOfInput()`
  4. Let the consumer finish. Never cancel it.
- If the analyzer throws, save what's finalized and create a new analyzer next time.

### 6.3 Raw draft (always)
Join the segments, with a new paragraph wherever the gap is 2.0 s or more. Apply the deterministic glossary replacements. Render the templates with AI placeholders **empty** (so `omitEmpty` drops them) and `{{title}}` set to its fallback. Write the full note right away with `{{processing}}` = `raw`. **From here on the note exists on disk.**

### 6.4 AI tidying — `Polisher` (on-device only)
- Model: `SystemLanguageModel(guardrails: .permissiveContentTransformations)`. Check `availability` before every run and log unavailable reasons as strings.
- Budget: `ctx = model.contextSize` (never hard-code it). Chunk input budget = `min(1200, (ctx − instructionTokens − 200) / 2)`. Chunk by paragraphs, then sentences, using `tokenCount(for:)`.
- **A new `LanguageModelSession` per chunk**, with `GenerationOptions(sampling: .greedy, maximumResponseTokens: inputTokens + 150)`.
- Instructions:
  ```
  You are a careful transcript editor. You receive a section of a spoken voice note.
  Return the same text with ONLY these changes:
  - fix punctuation, capitalisation and obvious speech-recognition errors
  - remove filler words (um, uh, er, "you know", "like" used as filler) and immediate repetitions or false starts
  - split into paragraphs where the topic shifts
  - use these spellings for project terms: {glossary}
  Do NOT summarise, paraphrase, reorder, add headings, add commentary, or change the speaker's first-person voice.
  Output only the edited text.
  ```
- **Fidelity guard:** lowercase both texts, split into words, and drop fillers. Reject the tidied chunk and use the raw chunk if the word-count ratio is outside `[0.80, 1.10]` or fewer than 85% of raw content words are kept. Any fallback sets `{{processing}}` to `tidied-partial`.
- Errors:
  - `exceededContextWindowSize`: split the chunk in half and retry once
  - `guardrailViolation`, `unsupportedLanguageOrLocale`, or anything else: use the raw chunk

### 6.5 Metadata — only what's used
**Step 1: work out the needed fields** (`MetadataRequirements`). Scan the effective note template, the filename pattern, the timeline format and the body settings:

| Field | Generated only if… |
|---|---|
| title | `ai.title` is on **and** `{{title}}` appears in a template, the filename, or the body heading. (The body heading always uses it, so in practice: if `ai.title` is on.) |
| summary | `ai.body.summary` is on, **or** `{{ai_summary}}` is used, **or** the timeline is on |
| keyPoints | `ai.body.keyPoints` is on, **or** `{{ai_key_points}}` is used |
| type | the note type is `Auto` **and** `ai.classifyType` is on **and** the type list isn't empty **and** `{{type}}` is used somewhere (template or timeline) |
| tags | `{{ai_tags}}` is used in the effective template and `maxCount > 0` |

The Front matter tab's **"Used AI values"** panel shows this result live, for example: "AI will generate: title, summary. Not generated: tags, key points, type."

**Step 2: generate with a dynamic schema.** Build a `DynamicGenerationSchema` containing only the needed fields:
- `title`: string, with the guide "at most 8 words, reuse the speaker's phrasing"
- `summary`: string, "one or two plain sentences; nothing not stated"
- `keyPoints`: array of 0–5 strings
- `type`: `anyOf` over the user's note type list
- `tags`: array of 0–`maxCount` strings. In `allowedOnly` mode, each item is an `anyOf` over the allowed list.

Convert it with `GenerationSchema(root:dependencies:)` and call `session.respond(to:schema:options:)`. Read the values from the `GeneratedContent` result. If **no** fields are needed, skip the model call entirely.

- Input: the tidied transcript if it fits within `ctx − 800` tokens. Otherwise map-reduce: one sentence per chunk, then generate from those sentences.
- A type the user picked, or the project's default type, is used as it is, and classification is skipped.
- Tags are normalised by the §5.3.5 rules after generation.
- If this step fails, AI placeholders stay empty (and `omitEmpty` drops them) and the title keeps its fallback.
- Prewarm the session when recording starts (only if at least one field is needed).

### 6.6 Final write
Re-render the templates with all values, and rewrite the note atomically. Rename the note and audio file per the filename pattern, append to the timeline, and show Done plus the notification.

## 7. Architecture

```
Murmur/
  App/            MurmurApp.swift, AppState.swift
  Settings/       SettingsStore.swift, Settings.swift (Codable), SettingsView + tabs, NoteTypesView.swift
  Projects/       Project.swift, ProjectStore.swift, FolderAccess.swift, VaultDetector.swift, ProjectPicker.swift
  Recording/      AudioRecorder.swift, LevelMeter.swift
  Transcription/  Transcriber.swift, SpeechAssets.swift, Transcript.swift
  AI/             Polisher.swift, Chunker.swift, FidelityGuard.swift, MetadataRequirements.swift,
                  MetadataGenerator.swift (DynamicGenerationSchema), TagNormalizer.swift, ModelStatus.swift
  Templates/      TemplateParser.swift (placeholders + filters), TemplateRenderer.swift, DateTokenFormatter.swift
                  (moment-style tokens → DateFormatter), FrontMatterBuilder.swift, YAMLEmitter.swift, Presets.swift
  Output/         NoteWriter.swift, NoteStyle.swift (standard/obsidian), Filename.swift, Timeline.swift, UnsavedNotes.swift
  UI/             PopoverView, RecordingView, ProcessingView, RecentNotesView, NewProjectSheet,
                  FrontMatterEditor (highlighting, autocomplete, preview), Onboarding/
  Support/        Log.swift, Permissions.swift
MurmurTests/
project.yml
```
- `AppState` is a `@MainActor @Observable` state machine: `idle → recording(project) → finalizing → tidying(i, n) → writing → done(URL) | error`
- `Transcribing`, `TextPolishing`, `MetadataGenerating` and `FolderAccessing` are protocols, with fakes for tests.
- The template engine is **pure** (no I/O, no model), so it can be fully unit-tested and is shared by front matter, filenames and the timeline.

## 8. Testing & acceptance

**Unit tests**
- **Principle tests:**
  - An empty template gives no front matter block.
  - A template without `{{ai_tags}}` gives no `tags` key, **and** the metadata generator is never asked for tags (checked on the fake).
  - None of the presets contain `ai_` placeholders.
- `TemplateRenderer`: every placeholder; moment-token formatting (`YYYY-MM-DD`, `dddd`, `[week] w` escapes); filters and chaining; whole-value vs in-quotes vs literal substitution; list splice mixing fixed and AI tags; `omitEmpty` for scalars, lists and list items; unknown placeholders left as they are
- `FrontMatterBuilder`: inherit / override / append; verbatim passthrough keeps comments and order; structural merge for collisions; `mergeLists`; invalid YAML goes to a body comment with no front matter
- `MetadataRequirements`: every row of the §6.5 table, including an empty type list and a user-picked type
- `TagNormalizer`: case, separator, prefix, `#` stripping, numeric-only tags dropped, dedupe, and `allowedOnly` rejecting anything outside the list
- `ObsidianStyle`/`StandardStyle` body rendering; `VaultDetector`; `SettingsStore`; `Filename`; `Chunker`; `FidelityGuard`; glossary; `FolderAccess` fallback
- Pipeline with fakes: raw note exists before tidying (with AI placeholders omitted); a failing generator still leaves a valid note
- Source check: no `URLSession`/`import Network`, no non-Apple model types

**Manual acceptance**
1. Fresh install with the *Minimal* preset: notes have only `created:` in the front matter. No tags appear anywhere in the vault.
2. Switch the project to *Obsidian basic*: `title`, `created`, `project` (a working link) and `audio` (embed link) appear in Obsidian's properties panel.
3. Add `tags:\n  - voice-note\n  - {{ai_tags}}` with `allowedOnly` and the list `[swift, audio, ux]`: tags include `voice-note` and only values from that list.
4. Remove `{{ai_tags}}` again: new notes have `tags: [voice-note]` only, and the "Used AI values" panel shows tags as not generated.
5. Rename the note types to `insight, blocker, win` and record with Auto: the type is one of those three. Empty the list: the picker disappears and no type is written.
6. A custom date `{{date:dddd D MMMM YYYY}}` renders as "Friday 25 September 2026".
7. Invalid YAML: the note saves without front matter, the block is kept in a `%% %%` comment, and a warning is shown.
8. Two projects with different folders and templates: each note uses its own project's folder and template.
9. Apple Intelligence off: the note saves, AI keys are omitted, and the title falls back.
10. `nettop` shows no connections from the app.

## 9. Build order

1. **Skeleton**: XcodeGen, sandbox, MenuBarExtra, `SettingsStore`, projects with bookmarks and vault detection
2. **Template engine**: parser, renderer, date tokens, filters, `FrontMatterBuilder`, YAML emitter, presets, plus the full unit test suite. Build this before the pipeline, because everything else writes through it.
3. **Capture + STT**: permissions, assets, recorder, transcriber, raw note written to the active project. *This alone is a usable app.*
4. **On-device AI**: chunker, polisher, fidelity guard, `MetadataRequirements`, dynamic-schema generator, tag normaliser, final rewrite
5. **Polish**: front matter editor (highlighting, autocomplete, preview, Used AI values), note types UI, hotkeys, timeline, recent notes, Open in Obsidian, Unsaved notes, notifications, launch at login

*Later ideas:* "Transcribe audio file…" import, re-tidy an existing note, append-to-last-note mode, a configurable body template (the same engine used for the note body), a per-project audio folder matching the vault's attachment folder.

## 10. Non-goals (v1)
Diarisation, editing notes inside the app, sync, iOS version, any non-on-device model, search UI, Obsidian plugin.

## 11. Reference notes for the implementer
- SpeechAnalyzer doesn't resample buffer input. Always convert to `bestAvailableAudioFormat`.
- Volatile results replace earlier volatile text. Only commit `isFinal` results.
- `SpeechTranscriber` doesn't support `AnalysisContext.contextualStrings` (only `DictationTranscriber` does), so the glossary is applied through replacement plus the prompt.
- The on-device context window is shared by instructions, input and output. Read `contextSize` rather than hard-coding it.
- Foundation Models supports runtime schemas through `DynamicGenerationSchema` → `GenerationSchema(root:dependencies:)` with `GeneratedContent` results. Use this rather than a fixed `@Generable` struct, so unused fields are never requested.
- Obsidian properties: types are text, list, number, checkbox, date (`YYYY-MM-DD`), date & time (`YYYY-MM-DDTHH:mm:ss`), and `tags`. Wikilinks in properties must be quoted. Nested properties are valid YAML, but Obsidian's properties UI can't edit them.
- Verify exact API signatures against the installed SDK. There have been small naming differences between WWDC sessions and the shipping SDK.

**SDK differences found (macOS 27 SDK, Xcode 27):**
- `GenerationOptions(sampling:…)` is deprecated. Use `GenerationOptions(samplingMode:temperature:maximumResponseTokens:)`.
- On macOS 27, `LanguageModelError.contextSizeExceeded` (plus `.guardrailViolation`, `.unsupportedLanguageOrLocale`) replaces the `LanguageModelSession.GenerationError` cases, which are deprecated there. The deployment target is 26.4, so the polisher handles both behind `#available(macOS 27, *)`.
- `SystemLanguageModel.contextSize` is back-deployed to 26.4.
