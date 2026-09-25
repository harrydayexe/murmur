# Murmur

A macOS menu bar app for capturing spoken thoughts, ideas and decisions while you work. Murmur records your voice, transcribes it on your Mac, tidies it lightly, and saves it as a Markdown note in your project's folder. That folder can be inside an Obsidian vault.

Everything happens on-device. Murmur has no network access, no analytics, and uses no cloud or third-party AI models.

## Features

- **One-click recording from the menu bar.** You see a timer, a level meter and a live transcript while you speak. Stop & Save when you're done, or discard the recording.
- **On-device transcription** with Apple's Speech framework.
- **Light AI tidying** with Apple's on-device model. It fixes punctuation, removes filler words and splits paragraphs, but it isn't allowed to paraphrase, summarise or reword. If a tidied section strays too far from what you said, Murmur keeps your original words instead.
- **AI title, summary and key points**, clearly labelled as AI-generated.
- **Your recordings are safe.** The audio and the raw transcript are written to disk before any AI step runs. The raw transcript is always kept in the note.
- **Projects.** Each project has its own save folder, so notes land where the work is.
- **Obsidian-friendly.** When a project's folder is inside a vault, notes use callouts, embedded audio and Obsidian-style properties.
- **Front matter you control.** Every front matter key comes from a template you write. Murmur never adds keys of its own, and AI values appear only where you put a placeholder for them.

## What a note looks like

```markdown
---
created: 2026-09-25T14:32:05
---

# Chose SQLite over JSON for the cache

> [!summary] Summary (AI-generated)
> Decided to move the local cache from JSON files to SQLite.

![[2026-09-25-1432-chose-sqlite-over-json.m4a]]

## Transcript

So we chose SQLite for the cache, because the JSON files kept getting corrupted…

> [!quote]- Raw transcript
> um so we chose sqlite for the cache because the json files kept getting corrupted…
```

## Requirements

- macOS 26.4 or later on Apple silicon
- Apple Intelligence turned on for tidying, titles and summaries. Without it, notes are still saved with the plain transcript.

## Status

Early and in active development. Customisation for templates, note types, AI tags, the timeline and hotkeys is planned. For now, anything beyond projects can be changed by editing the settings file. See [SPEC.md](SPEC.md) for the full design.

## License

[GPL-3.0](LICENSE)
