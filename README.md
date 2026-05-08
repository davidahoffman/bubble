# Bubble

A minimal markdown editor for Mac. Native Swift, no Electron, no dependencies.

![Built with Claude Code](https://img.shields.io/badge/built%20with-Claude%20Code-blueviolet)

## Features

- **Syntax highlighting** — headings, bold, italic, code blocks, links, checkboxes, tables
- **Keyboard-native** — Cmd+B/I/K, Tab/Shift+Tab list indent, Cmd+F find, auto-list continuation
- **Interactive checkboxes** — click the bracket to toggle
- **Multi-tab sidebar** — drag to reorder, rename inline, session restore on relaunch
- **Paste intelligence** — URLs auto-wrap as markdown links, base64 images stripped
- **Auto-save** — 1.5s after edits, plus session persistence across relaunches

## Install

```bash
git clone https://github.com/davidahoffman/bubble.git
cd bubble
swift build -c release
cp .build/release/Bubble /Applications/
```

Or just `swift run` to try it.

## Usage

| Shortcut | Action |
|----------|--------|
| Cmd+N | New document |
| Cmd+T | New tab |
| Cmd+O | Open file |
| Cmd+S | Save |
| Cmd+W | Close tab |
| Cmd+B | Bold |
| Cmd+I | Italic |
| Cmd+K | Insert link |
| Cmd+F | Find |
| Cmd+G | Next match |
| Cmd+Shift+G | Previous match |
| Cmd+0 | Toggle sidebar |
| Tab | Indent list |
| Shift+Tab | Outdent list |

## Stats

Built in one day. 1,800 lines of Swift across 9 files. ~4MB compiled.

## License

MIT
