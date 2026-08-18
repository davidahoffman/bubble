# Bubble — Agent Guide

Bubble is a native macOS markdown editor: Swift + AppKit (TextKit 1), built with SwiftPM. No external dependencies.

## Build & Run

```bash
swift build            # fast compile check (debug)
./build.sh             # release build + assembles + codesigns ./Bubble.app
open Bubble.app
```

## Test Harness

```bash
swift test
```

`Tests/MarkdownHighlightingTests.swift` drives a real `BubbleTextView` + `MarkdownTextStorage` headlessly — no window needed. This works because rendering is deterministic on text: `MarkdownTextStorage.processEditing()` re-highlights the full document on every character edit, so visual state is a pure function of the document string. Tests simulate keypresses (`insertNewline`, `setSelectedRange`) and assert on the attributes the highlighter produced (paragraph styles, colors, fonts).

**When to run it (required):**
- After any change to `Sources/Editor/` (`MarkdownTextStorage.swift`, `MarkdownStyles.swift`).
- After any change to input handling in `Sources/Views/EditorView.swift` (`insertNewline`, `insertTab`, `insertBacktab`, list continuation, paste).
- Before every commit that touches rendering or editing behavior.

**When fixing a rendering/input bug:** first add a failing test that reproduces it (document string + simulated keypress + attribute assertion), then fix, then confirm the test passes. A green `swift build` is not verification for this codebase — the bugs live in attributes, not compile errors.

## Known Footguns

- **`\s` matches newlines.** The highlighter regexes run over the whole document with `.anchorsMatchLines`, so `^` matches at every line start — and a leading `(\s*)` can swallow the newlines of blank lines above, inflating list indent levels and bleeding paragraph styles across paragraphs. Use `[ \t]` in line-anchored patterns, never `\s`. (This caused the first-list-item-indents-on-Enter bug.)
- **`lineRange(for:)` on a match range** spans every line the match touches. If a regex can cross a newline, the style applies to lines you didn't intend.
- **Highlight order matters** in `highlightFullDocument()` — later rules override earlier attributes on overlapping ranges.

## Repo Conventions

- Single executable target (`Sources/`), test target in `Tests/`. Test code can `@testable import Bubble` directly against the executable target.
- Commit messages: imperative summary line, body explains the why (see `git log`).
- `demo.md` is a scratch/demo document, not documentation.
