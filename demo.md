# Bubble

A markdown editor for Mac. Built it today.

## Why

I've used iA Writer since 2010. I love writing. I love that the world came back to markdown thanks to AI. Markdown apps are either too much (Obsidian, Notion) or too little (TextEdit). I wanted the thing that feels like home — monospaced, no WYSIWYG, no cloud, just files on disk and the words in front of you.

So I built it.

## What It Does

- **Real syntax highlighting** — headings scale, code blocks get dark backgrounds, links go blue, delimiters fade out
- **Keyboard-native** — Cmd+B/I/K, Tab/Shift+Tab indent, Cmd+F find, auto-list continuation
- **Interactive checkboxes** — click the bracket to toggle
- **Multi-tab sidebar** — drag to reorder, rename inline, session restore on relaunch
- **Paste intelligence** — URLs auto-wrap as `[text](url)`, base64 images get stripped

## NOT DOING

- Rich text / WYSIWYG — this is a *text* editor
- Image rendering — you're writing markdown, not previewing it
- Cloud sync — it's files on disk. Use git
- Plugins / extensions — scope is the enemy
- Vim mode — no.
- Mobile — it's a Mac app. that's it

## Behind the Scenes

One person + Claude Code. One day.

- **Time** — ~on and off for 5.5 hours (9:55am → 3:26pm)
- **Commits** — 25
- **Source** — 1,800 lines of Swift across 9 files
- **Framework** — SwiftUI + NSTextView (no Electron, no web)
- **Size** — ~4MB compiled. No dependencies

Most of the time was spent on feel — getting code blocks to have rounded dark backgrounds, making the sidebar not fight with macOS native tabs, tuning the list indentation so Tab/Shift+Tab works on multi-line selections. The kind of stuff that's invisible when it works and infuriating when it doesn't.

The AI pair wrote every line of Swift. I told it what I wanted, reviewed what it built, and pushed back when it was wrong. That's the workflow now.

**Try it:** `github.com/davidahoffman/bubble`
