# Margin•

Plain Markdown notes in a folder you own — and a calm reader for any folder of
Markdown you already have. Multiplatform (Flutter), no lock-in, no code
execution, no plugins.

Margin is the first app from [Annoyances Studio](https://github.com/annoyances-studio) —
small apps that fix day-to-day annoyances. This one started with "reading my own
Markdown is annoying."

It's a ground-up rework of an abandoned 2006-era .NET notepad (NotesWriter),
sharing nothing with that codebase beyond lineage and intent.

## What it does

- **Your notes, your files.** Notes are plain `.md` files in a folder you
  control — edit them here or in any other tool. No database, no lock-in.
- **Companion mode.** Open *any* plain Markdown folder read-only — documentation,
  a wiki, a Claude-generated project — with in-app `.md` link navigation,
  backlinks, full-text search, and folder overviews. Works on local folders and
  on shared cloud folders (OneDrive / WebDAV).
- **Sync that stays yours.** Pluggable storage backends (local folder, WebDAV,
  OneDrive) with clone-then-sync and offline-first; a conflict keeps both copies
  rather than overwriting.
- **Reads and writes like Markdown should.** Live-styled editor, rendered
  preview, tables, attachments (paste / drag / download), rich bidirectional
  copy-paste, folder notes (`README.md`).

## Status

Feature-complete for daily use. Builds and runs on **Windows** and **Android**;
**macOS / Linux** desktop scaffolding is in place (build on those hosts or via
CI); **iOS** is planned. Remaining work is tracked in [BACKLOG.md](BACKLOG.md),
and the architecture and rationale live in [DESIGN.md](DESIGN.md).

## Principles

- Notes are plain Markdown files in a folder the user controls. No lock-in.
- Storage is a dumb folder; the app provides sync and conflict handling.
- Folder-enforced organization.
- First-class on both desktop and mobile (Flutter).
- Private. The user decides where notes live.

The app does not run code, is not an IDE, and has no plugin system.

## AI assistance

Margin is developed openly with the help of Claude (Anthropic). We state this
plainly. The code and design are open source so the work can be inspected,
reused, and given back.

## License

Mozilla Public License 2.0 (MPL-2.0). See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Commercial use is allowed, but modifications to Margin's own source files must be
published. The project name and branding are handled separately as trademarks.
