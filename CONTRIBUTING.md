# Contributing to Margin

Thanks for your interest. Margin is open source and contributions are welcome —
but it is a **solo-maintained, opinionated** project, so a few expectations up
front keep everyone's time well spent.

## How this works

- **Open an issue before non-trivial work.** For anything beyond a small fix,
  describe what you want to change and why, and wait for a thumbs-up before
  writing it. This protects your effort as much as the project's direction — a
  big PR that doesn't fit is a loss for both of us.
- **Everything is reviewed.** All changes land through a pull request and are
  reviewed before merging. Direct pushes to `main` are not accepted.
- **No timeline.** This is a side project. Reviews and replies may be slow, and
  that's expected — please don't read quiet as a no (or a yes).
- **Fit matters, and some things will be declined.** Changes that cut against
  Margin's direction (below) may be turned down even if they work. That's normal
  and not a judgement of the work.

## What Margin is (and isn't)

- Notes are **plain Markdown files** in a folder the user controls. No lock-in,
  no proprietary formats.
- **No code execution, no plugin system, never an IDE.** The `StorageBackend`
  interface is the extension point; new backends are welcome, arbitrary code is
  not.
- **AI assistance is disclosed openly** — see the README. Contributions made with
  AI help are fine; say so where it's relevant.
- **Few dependencies we own** over fragile ones.

If you're looking for where help is useful, `BACKLOG.md` is the roadmap and
`DESIGN.md` explains the architecture and the reasoning behind it.

## The bar for a PR

Margin ships with a full test suite and keeps it green — please hold that line:

- `flutter test` passes and **new behavior comes with a test**.
- `flutter analyze` is clean.
- Match the surrounding style; every Dart file carries the **MPL-2.0 header**
  (copy one from a neighbor).
- User-facing strings go in `lib/l10n/app_en.arb` + `app_es.arb` (run
  `flutter gen-l10n`); never hard-code UI text.
- Keep commits focused and the message explaining the *why*.

`CLAUDE.md` has the practical build/run notes (Flutter lives at
`C:\src\flutter\bin` on the reference machine; the suite must stay green).

## Licensing

By contributing, you agree your contribution is licensed under the project's
**Mozilla Public License 2.0** (MPL-2.0), the same as the rest of Margin. No CLA.

## Security

Please **do not** open a public issue for a security problem. See
[SECURITY.md](SECURITY.md) for private reporting.
