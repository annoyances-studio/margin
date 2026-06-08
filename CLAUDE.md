# CLAUDE.md — Margin

Operational guide for Claude working in this repo. Deep architecture/rationale
lives in `DESIGN.md`; this file is the practical "how to work here" + gotchas.

## What this is

**Margin** — a multiplatform (Windows/macOS/Linux desktop + Android/iOS) open-
source Flutter Markdown notes app. Notes are plain `.md` files in a folder the
user owns (a "dumb folder"). Pluggable `StorageBackend`s; **no plugin system,
no code execution** (never an IDE). AI assistance is disclosed openly.

## Repo location & history (read this first)

- **The code lives at `C:\Code\margin`.** Always work here.
- The project began in a `noteswriter` repo, then moved to `margin`. The session
  working-directory path may still say `...imagina-noteswriter...` — **ignore
  that; the real repo is `C:\Code\margin`**. If you ever see two repos, this is
  the one.
- Git remote: `origin = https://github.com/danmarce/margin-app.git`, branch `main`.
- Commit/push only when the user asks. End commit messages with:
  `Co-Authored-By: Claude <model> <noreply@anthropic.com>`.

## Environment & build (Windows)

- **Flutter is NOT on the default PATH.** It's at `C:\src\flutter\bin`. In
  PowerShell prepend it: `$env:Path = "C:\src\flutter\bin;" + $env:Path` before
  any `flutter`/`dart` command. (Git Bash doesn't see flutter at all — use the
  PowerShell tool for Flutter commands.)
- Common commands (from `C:\Code\margin`):
  - Analyze: `flutter analyze`
  - Test: `flutter test` (full suite is ~280+ tests and must stay green)
  - Regenerate localizations after editing `lib/l10n/*.arb`: `flutter gen-l10n`
  - Windows build: `flutter build windows --release` → `build\windows\x64\runner\Release\` (zip the **whole folder**, not just the exe)
  - Android: `flutter build apk --release` (+ the OneDrive `--dart-define`s below)
- **`LNK1104: cannot open file 'margin.exe'`** on a Windows build = the running
  app holds the binary. Fix: `Stop-Process -Name margin -Force` (it autosaves on
  focus-loss) then rebuild.
- **OneDrive build flags** (required for OneDrive sign-in to work; client id is
  public, redirect URI is registered in Entra):
  ```
  --dart-define=ONEDRIVE_CLIENT_ID=0304331a-6dd1-4374-8a6d-208de756ea14
  "--dart-define=ONEDRIVE_REDIRECT_URI=msauth://com.lordofthedummies.margin/3bApnScojg4cQfTjSK14EAemu0k%3D"
  ```
  Windows desktop is built **without** these (OAuth is mobile-only; desktop uses
  the OneDrive-synced local folder).
- Android package: `com.lordofthedummies.margin`. Release is signed with the
  **debug keystore** (matches the Entra signature hash, so OneDrive works on
  release APKs). A possible future rebrand → `es.annoyanc.margin`.
- `pip`/external installs hit a corporate **SSL-intercepting proxy**; use
  `--trusted-host pypi.org --trusted-host files.pythonhosted.org` if needed.

## Architecture (1-minute map; see DESIGN.md for depth)

- `lib/src/storage/` — `StorageBackend` (list/exists/read/write/delete, repo-
  relative `/` paths, reject `..`). Implementations: `LocalFolderBackend`
  (+ `MovableBackend` atomic rename, lock-retry/timeout guard), `WebDavBackend`,
  `OneDriveBackend` (Graph), `MemoryBackend` (tests). The interface IS the
  extensibility — no plugins.
- `lib/src/folio/` — `Folio` (a backend + validated `properties.yaml`), `Note`
  (YAML frontmatter + body), `NoteProperties` (the `.md.yaml` **sidecar**:
  title/tags/updated **index** + `view`).
- `lib/src/content/` — `ContentService` (tree, notes, folders, attachments,
  sidecar maintenance, empty-folder hide/prune), `markdown_convert.dart`
  (md↔html, plain, data-URI/remote image rewriting — pure, testable).
- `lib/src/sync/` — `SyncEngine`/`SyncPlanner`/`SyncState`: three-way sync over
  **any two backends** (this is the sync extensibility). Conflict = keep-both
  copy. **Emptying guard**: withholds a wipe-everything plan for confirmation.
- `lib/src/ui/app_controller.dart` — the heart. Owns the open Folio, tree,
  selected note, editing buffer. **Clone-then-sync**: remote Folios run against
  a local cache (`Margin/<UUID>/`) with the remote as a sync peer; offline-first
  open; auto-sync after save; per-note freshness pull on open; note search over
  the sidecar index; rich copy/paste; attachment save. Operations are
  **serialized** (`_opChain`/`_serialize`/`_run`) so background sync never races
  mutations — but **reads (note open) run outside the queue** to stay responsive.
- `lib/src/ui/` — `MarginApp` (root, lifecycle save-on-background), `FolioScreen`
  (desktop two-pane + phone 3-page pager), `OpenFolioScreen` (landing),
  `clipboard_service.dart` (win32 CF_HTML on Windows, plain elsewhere).
- `lib/src/desktop/` — window/tray (`window_manager`, `tray_manager`),
  run-at-login (`StartupService`, `--minimized` flag), file reveal.
- `lib/src/mobile/` — Android Back→background (method channel in MainActivity).

## Conventions (match the existing code)

- Every Dart file starts with the **MPL-2.0 header** (copy from any neighbor).
- **i18n**: user-facing strings go in `lib/l10n/app_en.arb` + `app_es.arb` (with
  `@key` description in `en`), used via `AppLocalizations.of(context)`. Run
  `flutter gen-l10n` after edits. Never hard-code UI strings.
- **Testing discipline**: new behavior gets a test; keep the suite green +
  `flutter analyze` clean before considering work done. Pure logic is extracted
  into testable functions (e.g. image transforms take async I/O callbacks).
  Services are injectable (settings/credentials/clipboard/http/cacheRoot) so the
  controller is unit-testable with in-memory fakes.
- **Security constraints (hard rules):** secrets (WebDAV passwords, OneDrive
  tokens) go to the **OS keystore** via `CredentialStore` — **never** into
  `properties.yaml` or the repo. No code execution. No third-party plugin system.
- Prefer **few dependencies you own** over fragile packages (we dropped
  `rich_clipboard` for a hand-rolled win32 clipboard after it broke the build).

## Gotchas seen in the wild

- **OneDrive/Dropbox locks**: OS-synced folders briefly lock files mid-sync.
  `LocalFolderBackend` retries transient access-denied (errno 5) with backoff and
  uses atomic moves for rename. OneDrive can also leave **empty folders** after a
  remote delete — `open()`/sync prune them; the tree hides empty unmarked dirs.
- **OneDrive "Processing changes" stuck** = the OneDrive *client*, not Margin
  (restart it).
- `SelectionArea` wraps the preview for cross-block selection; watch for it
  fighting link taps.
- Cache writes from background tasks are **serialized** to avoid racing sync.

## Current status

Feature-complete enough for daily use: local/device/WebDAV/OneDrive backends,
clone-then-sync + offline-first, rich bidirectional copy/paste (incl. image
download/attach), note search, run-at-login (+start minimized). All on `main`,
binaries build for Windows + Android. Open backlog: landing "Recent Folios" +
consolidated open/connect button, OneDrive in-app folder browser, optional
full-text "deep search".
