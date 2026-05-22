# Margin

A multiplatform note-taking application. Plain Markdown files in a folder you
control, synced across desktop and mobile through pluggable storage backends.

Margin is a ground-up rework of an abandoned 2006-era .NET notepad project
(NotesWriter). It shares nothing with that codebase beyond lineage and intent.

## Status

Design phase. No application code yet. See [DESIGN.md](DESIGN.md) for the full
specification.

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

To be selected before publishing.
