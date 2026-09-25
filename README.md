# Murmur

**Talk through an idea, and get a tidy Markdown note in your project folder.**

Murmur lives in your Mac's menu bar. Click it and speak, and Murmur saves what you said as a clean, readable note, right next to the work it's about. It's built for capturing thoughts, ideas and decisions while you work, without breaking your flow. Notes can go straight into an Obsidian vault.

**Private by design.** Everything happens on your Mac. Murmur can't connect to the internet, collects no analytics, and never sends your voice or words to a cloud service.

## Features

- **Record from the menu bar in one click.** While you speak you see a timer, a level meter and a live transcript. Stop & Save when you're done, or discard the recording.
- **Transcription on your Mac**, using Apple's built-in speech recognition.
- **Light tidying that keeps your words.** Murmur fixes punctuation, removes filler words like "um" and "you know", and splits the text into paragraphs. It doesn't paraphrase, summarise or reword. If a tidied section strays too far from what you said, Murmur keeps your original words instead.
- **A title, summary and key points** for every note, clearly labelled as AI-generated.
- **Your recordings are never lost.** The audio and the raw transcript are saved before any tidying happens, and the raw transcript is always kept in the note.
- **Projects.** Give each project its own folder, so notes land where the work is.
- **Made for Obsidian.** When a project's folder is inside a vault, notes use callouts, embedded audio and Obsidian properties.
- **Front matter you control.** Murmur only adds the properties you ask for in your own template, nothing more.

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

- A Mac with Apple silicon, running macOS 27 or later
- Apple Intelligence turned on for tidying, titles and summaries. Without it, Murmur still saves your notes with the plain transcript.

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask harrydayexe/tap/murmur
```

Or download the latest `Murmur-<version>.zip` from [Releases](https://github.com/harrydayexe/murmur/releases), unzip it and move `Murmur.app` to your Applications folder.

To update, run `brew upgrade --cask murmur` or download the new release.

## Getting started

1. Open Murmur. A waveform icon appears in your menu bar.
2. Click it, choose **New project…**, and pick the folder where notes should be saved.
3. Click **Record**. The first time, macOS asks for access to your microphone and speech recognition.
4. Speak, then click **Stop & Save**. Your note appears in the project's folder a few moments later.

## Status

Murmur is early and in active development. Coming soon: a global hotkey, and settings for templates, note types, AI tags and the timeline.

## License

[GPL-3.0](LICENSE)
