# Bubble

A markdown editor for Mac. Built it today.

## Why

I love writing. I love that the world came back to markdown thanks to AI. I haven't found an app I love for local markdown editing. So I built it.
## What It Does

- **Keyboard-native**
- **Interactive checkboxes**
- **Multi-tab sidebar**
- **Paste intelligence**

## What It Doesn't Do (on purpose)

- Rich text / WYSIWYG — this is a *text* editor
- Image rendering — you're writing markdown, not previewing it
- Cloud sync — it's files on disk. Use git
- Plugins / extensions — scope is the enemy
- Vim mode — no.
- Mobile — it's a Mac app. that's it

## Behind the Scenes

One person + Claude Code. Half a day.

- **Time** — ~on and off for 5.5 hours (9:55am → 3:26pm)
- **Commits** — 25
- **Source** — 1,800 lines of Swift across 9 files
- **Framework** — SwiftUI + NSTextView (no Electron, no web)
- **Size** — ~4MB compiled. No dependencies

Most of the time was spent on feel. 

Never opened xCode. I told it what I wanted, reviewed what it built, and pushed back when it was wrong. That's the workflow now.

**Try it:** `github.com/davidahoffman/bubble`
