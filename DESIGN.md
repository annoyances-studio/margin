# Margin — Design Document

Margin is a multiplatform note-taking application. This is a ground-up rework of
an abandoned 2006-era .NET notepad project (NotesWriter). It shares nothing with
that codebase beyond lineage and intent.

## On AI assistance

This project is developed openly with the help of Claude (Anthropic). We state
this plainly rather than hiding it. The code and design are open source so the
work can be inspected, reused, and given back to the community.

## Status

Shipping. Margin is feature-complete for daily use and released (Windows +
Android; macOS/Linux/iOS build on their host or via CI). This document is the
standing record of **architecture and rationale**; the live task list is
`BACKLOG.md` and the practical "how to work here" is `CLAUDE.md`.

## Name

Margin. Chosen from the working candidates (Folio, Margin, Notesmith). The old
project was called NotesWriter (never published); an earlier one was NotesLite.

## License

Mozilla Public License 2.0 (MPL-2.0). Chosen as a balance: it allows commercial
use, is compatible with mobile app stores, but requires that modifications to
the project's own source files be published (file-level copyleft). This blocks
silently closing the core while keeping distribution practical.

The MPL governs the code. The project name and branding ("Margin") are handled
separately as trademarks; the license does not grant rights to them.

Source files carry the standard MPL header (Exhibit A) once code exists. AI
assistance is disclosed in the NOTICE file and README.

---

## Goals

- Replace OneNote for personal daily use. The app is niche by design. If it
  proves useful, it will be published.
- First-class on both desktop and mobile.
- Open source.
- Private. The user owns their storage and decides where notes live.

## Non-goals

- The app does not run code. Fenced code blocks are rendered, never executed.
- It is not an IDE and does not aim to replace one.
- No plugin system.

---

## Core principles

1. Notes are plain Markdown files in a folder the user controls. No lock-in.
   The default experience is files you can also read with any other tool.
2. Storage is a dumb folder. The app provides sync and history; the backend
   only needs to store and retrieve files.
3. Folder-enforced structure. Organization comes from directories, not tags or
   a flat pile of files.
4. Adapt the same model to each platform rather than maintaining divergent
   designs.

---

## Technology

- Flutter, single codebase for desktop and mobile. (Also a deliberate learning
  goal for the author.)
- Markdown: GitHub-Flavored Markdown (GFM) — tables, task lists, strikethrough,
  fenced code blocks (rendered only).
- Credentials and encryption keys: OS secure keystore via `flutter_secure_storage`
  (Keychain on Apple platforms, Keystore on Android, platform equivalents on
  desktop).

---

## Storage architecture

A single storage interface with multiple backend implementations. Everything
above the interface (sync engine, conflict handling, UI) is backend-agnostic.

```
StorageBackend (interface)
  list(path)        -> entries with modified-time / etag / hash
  read(path)        -> bytes
  write(path, bytes)
  delete(path)
```

### Backends

| Backend      | Server software | Desktop | Mobile | Notes                              |
|--------------|-----------------|---------|--------|------------------------------------|
| Local folder | none            | yes     | yes    | Zero-config default                |
| WebDAV       | none (NAS/Nextcloud already speak it) | yes | yes | Cross-platform backbone; URL + credentials |
| SMB          | none (NAS native) | yes   | poor   | Mobile sandboxing makes this painful |
| NFS          | none            | yes     | no     | Desktop / NAS only                 |
| Cloud (Dropbox, Drive, etc.) | account + API | yes | medium | Later                       |
| Git remote   | git host or self-hosted | yes | poor (auth) | Optional, later, behind the same interface |

WebDAV is the cross-platform backbone: it is the only backend fully viable on
both desktop and mobile, because the app speaks the protocol directly rather
than relying on the OS to mount anything. The UI should present only the
backends the current platform actually supports.

### Backend feasibility (which are realistic)

Three connection mechanisms decide feasibility more than the provider does:

1. **OS-mounted/synced folder → `LocalFolderBackend`** (no app code). Covers
   almost everything on desktop.
2. **In-app protocol/REST backend** (a `StorageBackend`, sometimes + OAuth).
   Needed on mobile, and for self-hosted protocols.
3. **OS-native / entitlement-heavy** (kernel mounts, Apple frameworks) —
   generally not worth building.

Desktop (Windows/macOS/Linux — all first-class Flutter targets) can mount or
sync nearly anything to a folder, so the genuinely hard problem is **mobile**.

- **WebDAV** — shipped; in-app REST; all platforms; no OAuth.
- **SFTP** — best next backend; pure Dart (`dartssh2`); all platforms; no
  OAuth. Needs **two auth modes: password and SSH key** (key file + optional
  passphrase), both supported by `dartssh2`.
- **Git** — two separate ideas. (a) A read-write *sync* backend over a local
  clone (commit/push) — desktop via the system `git` CLI or an external client
  keeping a synced clone — **not built**. (b) A read-only *companion* —
  **shipped on Android**: JGit clones a repo into app storage (Git-LFS
  materialized, a one-time PAT in the keystore), Refresh pulls, and Margin
  browses the working tree read-only via `LocalFolderBackend`. See
  **Companion mode**. JGit is JVM-only, so the companion is Android-first.
- **SMB/CIFS** — desktop via OS mount/UNC path; mobile not realistic (sandbox;
  only immature Dart libs). No in-app backend.
- **NFS** — desktop via OS mount only; no Dart client. No backend.
- **OneDrive** — **shipped** as the prototype mobile cloud provider: Graph REST
  + OAuth (`flutter_web_auth_2`), token in `CredentialStore`, clone-then-sync
  against a local cache. Desktop still prefers the OneDrive-synced local folder.
- **Google Drive / Dropbox** — not built; desktop free via the provider's sync
  folder; mobile would need the same OAuth + REST treatment as OneDrive. Build
  on demand: Dropbox simplest, Google Drive last (restricted-scope verification
  / CASA audit is costly).
- **iCloud** — synced folder on macOS and Windows (iCloud app); iOS-direct is
  app-container / document-picker only (entitlements, Apple Developer account);
  Android/Linux: none.

Roadmap: WebDAV (done) → OneDrive (done, prototype mobile cloud) → SFTP
(password + SSH key, **not yet built**) → further mobile OAuth clouds on demand.
Everything else is handled by a mounted/synced folder on desktop.

### Self-hosting story

Rather than "install a notes server," a power user can run a small Docker
container that publishes a chosen folder over WebDAV. The app stays a dumb
client; the data remains plain files in a folder the user can also access by
other means.

### Sync for free via a cloud-synced folder

Because a repository is just a folder of plain files, the simplest "sync" needs
no app support at all: put the repository inside a directory that a cloud client
already keeps in sync (OneDrive, Dropbox, iCloud Drive, Nextcloud, ...). The
local-folder backend reads and writes it; the cloud client handles propagation.
This is the recommended easy path on desktop and reinforces the core principle:
your notes are openable safely anywhere, by Margin or anything else.

### Why not Git as the foundation

Git was considered as the primary sync mechanism but rejected as the
foundation. It assumes the user has somewhere repositories can live, and it
brings auth pain on mobile (SSH keys, tokens on a phone). Because the app owns
its own sync and conflict logic, Git's merge machinery is unnecessary. Git
remains a possible opt-in backend for users who want real history, but it is
not required. (Update: a read-only git-*read* backend has since shipped as a
**companion** feature on Android — pull-only, LFS-aware; see **Companion mode**.
That is browsing a repo, not adopting Git as the read-write sync foundation,
which is what this section rejects.)

---

## Sync and history

History model: current state only. No app-managed version history. A dumb
folder has no history of its own, and conflict-copy covers the divergence case.

Save and sync are two distinct layers:

```
Layer 1 - SAVE   (edits -> local file)
  - debounced autosave while typing
  - force-flush on: switching notes, app backgrounding, minimize-to-tray, close
  - synchronous and instant (a local file write)

Layer 2 - SYNC   (local files <-> backend)
  - pull / sync on open
  - commit (save) and push after edits
  - runs in the background; can be slow or offline without blocking the UI
  - all defaults are user-configurable
```

The save/sync split is what makes fast note-switching safe: switching a note
force-flushes the local save first (instant, local), then changes the view;
sync catches up in the background. The same flush on app-pause protects against
the OS killing a backgrounded mobile app.

### Conflict handling

Each device keeps a small local sync-state record (last-synced hash per file).
On sync, a three-way comparison decides the action:

- Local changed, remote did not -> push.
- Remote changed, local did not -> pull.
- Both changed since last sync -> conflict.

On conflict, the app warns the user and creates a new copy of the conflicting
file rather than overwriting, for example:

```
note.md
note (conflict, Phone, 2026-05-22).md
```

The user reconciles manually. No automatic merge.

### Fast, resumable transfers

Hashing a file means reading its bytes — and for a remote, downloading them. A
big image-heavy Folio makes that cost visible, so the engine avoids re-fetching
bytes it doesn't need:

- **Content-hash cache.** The sync-state record keeps, per side, a
  `fingerprint → content-hash` memo. A `fingerprint` is a cheap backend token —
  OneDrive's `quickXorHash`, a WebDAV `ETag`, or `size:mtime` as a fallback
  (`StorageEntry.fingerprint`). If a file's fingerprint is unchanged since last
  sync, its stored hash is reused instead of re-reading the file. The content
  hash stays the canonical, cross-backend comparison key (the planner compares
  local vs remote hashes directly), so the cache is a pure speed-up: a cold or
  stale cache costs work, never correctness. A fingerprint is only ever matched
  against the *same* backend's prior record, so a local `size:mtime` and a
  remote `quickXorHash` never meet.
- **Single-download first clone.** A naive clone would fetch every file twice —
  once to hash it into a snapshot, once to pull it. When the base and the local
  side are both empty (a fresh clone), the engine instead lists the remote by
  metadata only and hashes each file from the one copy it downloads while
  pulling it. `properties.yaml` is pulled first so an interrupted clone is still
  a reopenable Folio.
- **Checkpoint & resume.** During a long run the engine periodically calls back
  with a *partial* sync-state that is safe to persist (every path in it is
  genuinely in sync). If a run is interrupted (dropped connection, screen off),
  the next run resumes from the last checkpoint — the already-transferred bytes
  are not fetched again — instead of starting over. A clone that fails partway
  still **adopts the partial cache** (offline-first): the user lands on the
  notes that arrived, with the failure surfaced as a retryable sync error rather
  than a dead error screen.
- **Keep-awake (Android).** A long sync/clone holds a partial CPU wake lock and
  a high-performance Wi-Fi lock (`KeepAwake`, over the `margin/app` channel) so
  the screen turning off can't suspend the process or idle Wi-Fi mid-transfer
  and drop the connection. Both carry a timeout so a crash can't leak them, and
  they're released as soon as the run finishes. Best-effort and no-op off
  Android; true headless background sync (a foreground service) is intentionally
  **not** done — see BACKLOG.

#### Surfacing & resolution (design)

The guiding principle is **never lose data, even for a user who ignores the
problem.** Sync stays fully automatic — it never blocks editing to ask a
question. A conflict just leaves both versions on disk (the original wins the
canonical path; the divergent copy gets the `(conflict, <label>, <date>)`
suffix) and surfaces a *passive* cue.

- **The cue is derived from the tree, not from the sync event.** A conflict is
  "present" whenever a `(conflict, …)`-named file exists in the Folio —
  recomputed on every tree refresh. This makes it **durable** (survives restart),
  **device-independent** (the copy syncs everywhere, so any device shows it), and
  **self-clearing** (the moment the last conflict file is gone, the cue clears on
  every device after sync). `SyncResult.hadConflicts` is only used to *flash*
  attention right after the sync that created the copy.
- **Visual:** tint the in-app `AppBar` (it is our widget, not OS chrome — safe to
  recolor cross-platform) with the separator-line color while conflicts exist,
  plus a count badge ("3 to resolve") and a row badge on the conflict files so
  the user can *find* them. The global tint says "something's wrong"; the row
  badge says "here."
- **The marker is the filename suffix itself** (not a hidden sidecar flag).
  Resolution is then just the file ops the user already has — **Delete** and
  **Rename** — and the cue clears as a side effect, with no dedicated "dismiss"
  button and no hidden state:
  - *Keep server, drop mine* → delete the conflict copy.
  - *Keep mine, drop server* → delete the original, rename the copy onto it.
  - *Keep both as real notes* → rename the copy to a meaningful name (dropping
    the suffix). This promotes it to a first-class note **and** clears the cue in
    one action. A filename marker clears on rename; a sidecar flag would not,
    leaving a normally-named note still secretly flagged — which is why the
    suffix wins.
- **Discoverability sugar:** a "Resolve…" entry in the conflict row's context
  menu that just opens the normal rename dialog pre-filled with the stem minus
  the suffix. Pure shortcut to rename; makes the comfortable path obvious.
- **Stacking is allowed.** A lazy user who never resolves just accumulates
  `note (conflict, Phone, d1) (conflict, Desktop, d2).md`; nothing is ever lost,
  the count badge just grows. We explicitly tolerate this.
- **Desktop's payoff is *compare*.** Because "keep both" / careful merge matters
  most for long notes, a side-by-side / diff of `note.md` vs. its conflict copy
  (with quick jump between the same-stem pair) is the one genuinely new build
  item; everything else rides on existing file sync + tree rendering. On phone
  the user just acknowledges and defers to a bigger screen — which works for free
  because the cue and files travel with sync.

---

## Repository and metadata

One repository is open at a time. The user can switch between repositories.

Folder-enforced structure: no `.md` files at the repository root. All notes
live inside directories.

### Repository identity

Each repository has a random UUID, generated once at creation. It ties the
local sync-state and the stored credentials/keys to the repository regardless
of which access route reached it. The root `properties.yaml` is the marker that
tells the app it is dealing with the same repository.

### Three metadata layers

Root `properties.yaml` — identity and how to reach the repository:

```yaml
schemaVersion: 1
id: 7f3c9a1e-...        # random UUID, generated once at creation
name: "My Notes"
created: 2026-05-22T10:00:00Z
updated: 2026-05-22T14:30:00Z
appVersion: "0.1.0"     # for upgrade migrations / compatibility warnings
# Alternate routes to the same data. Discovered after first connection,
# used as fallback or convenience. Never contains credentials.
endpoints:
  - type: webdav
    url: https://nas.local/dav/notes
  - type: smb
    path: \\nas\notes
```

Folder `properties.yaml` — per-directory metadata:

```yaml
title: "Project X"
created: 2026-05-22T...
# sort order, icon/color, etc. as needed
```

Note frontmatter — at the top of each `.md`:

```yaml
---
title: "Meeting notes"
created: 2026-05-22T...
updated: 2026-05-22T...
tags: [work, q2]
---
# Body in GitHub-Flavored Markdown
```

### Endpoints and the bootstrapping rule

The `endpoints` list cannot be used to make first contact, because reading it
requires access to the folder in the first place. Therefore:

- Creating a new repository writes a fresh `properties.yaml`; the user may add
  extra access paths.
- Opening an existing repository reads the paths already present and offers them
  as alternate routes (for example, a faster LAN SMB path discovered after
  connecting once over WebDAV).

### Credentials

Credentials are never written to `properties.yaml` (the file syncs with the
notes). Addresses and paths live in `properties.yaml`; credentials live in the
OS secure keystore, keyed by the repository `id`.

### Attachments

Each directory has an `_attachments/` folder for embedded files:

```
Project X/
  properties.yaml
  meeting-notes.md
  _attachments/
    diagram.png
```

Keeping attachments local to the directory that uses them makes a future
"clean up unused attachments" scan simple and well-scoped.

---

## User interface

The core model is "tree plus editor," with tree visibility adapting to the
platform:

| State        | Desktop            | Mobile              |
|--------------|--------------------|---------------------|
| Tree visible | panel expanded     | slide-over open     |
| Tree hidden  | collapsed to editor| drawer closed (note view) |

### Mobile

- Note view is primary. A slide-over drawer reveals the folder tree.
- The drawer overlays the note (does not push it aside).
- New-note action via a floating button; tapping the title opens rename/metadata.
- Switching notes from the drawer force-flushes the current note's save first.

### Desktop

- Two-panel layout: persistent folder tree on the left, editor on the right.
- The tree panel collapses to leave only the editor.
- Two panels are preferred over three. Folders are few and notes are many, so a
  notes-as-tabs or three-panel layout scales poorly; a clean collapsible
  two-panel layout fits better.
- Minimize to tray. Tray menu: Open, Sync now, Quit.
- A small Settings dialog; on desktop it offers "start at login" (run on logon).
- **Custom frameless chrome (realized):** the OS title bar is hidden
  (`window_manager` `TitleBarStyle.hidden`) and Margin draws one merged bar — app
  mark, history nav, the note breadcrumb + note search, the view-mode control,
  the overflow menu, and its own window buttons (macOS keeps native
  traffic-lights and moves the mark to the right). A **folio switcher** + the
  folder actions sit atop the tree; a **status bar** carries the full path, caret
  Ln/Col, and sync state; the OS window title tracks the open note's name. The
  tree opens **collapsed by default** (open/closed folder icons). When a desktop
  window is narrowed to the phone layout, its header becomes draggable and gains
  the window buttons, so the frameless window is controllable at any size.

### Editor (realized approach)

The original intent was a true block WYSIWYG editor. That was attempted with a
rich-editor engine (appflowy_editor) but its latest release does not compile on
the current Flutter SDK (a newly-required `TextInputClient` method is
unimplemented). Rather than pin an old SDK or take another heavy dependency, the
editor follows what the old NotesWriter did with its rich-text control: extend
the editing primitive.

`MarkdownEditingController` (a `TextEditingController` subclass) styles Markdown
inline as you type — headings render larger/bold, `**bold**`, `*italic*`,
`~~strike~~`, `` `code` ``, block quotes, fenced code — while the stored text
stays raw Markdown. Benefits: no heavy dependency or SDK-compat risk, exact
round-trip, and "the formatting is the typing" (no toolbar or shortcuts), which
suits mobile especially. Markers stay visible but dimmed.

View modes: **Editor** (this inline-styled view, default), **Split** (editor +
rendered preview), **Preview** (read-only render). True block WYSIWYG remains a
future option if a compatible engine becomes available.

### Shared behaviors

- A sync indicator is always visible: synced, syncing, conflict, offline.
  Tapping it shows details and a "sync now" action.
- Conflicts surface as a banner offering to create the conflict copy.
- Settings cover backends/endpoints, sync defaults (on-open, after-edit, all
  toggleable), credentials, and attachment cleanup.

### Terminology

A whole collection of notes is a **Folio** (the folder the user owns) — both in
the UI and in the code: the `Folio` type, `FolioProperties`, `lib/src/folio/`,
and the `AppController` API (`hasFolio`, `folioName`, `closeFolio`, …). Some
low-level storage/sync comments still say "repository-relative path"; the
persisted settings key and `properties.yaml` field names are kept as-is for
backward compatibility.

### Internationalization

UI strings live in ARB files under `lib/l10n/` and are exposed through the
gen_l10n-generated `AppLocalizations` (configured in `l10n.yaml`). Adding a
language is one file: copy `app_en.arb` to `app_<locale>.arb`, translate the
values, and rebuild. The app follows the OS locale. Model-layer exception
messages are not yet localized.

---

## Companion mode (read-only browsing)

Beyond editing its own Folios, Margin opens **any** plain-Markdown folder
read-only — documentation, a wiki, a Claude-generated knowledge base — without
writing anything into it (no `properties.yaml`, no sidecars). Detection: a folder
with no root `properties.yaml` opens in *browse* mode. It renders the tree and
Markdown, follows relative `.md` links in-app, offers deep/full-text search and
backlinks, and opens on an overview (root `CLAUDE.md`/`README.md`, else a
synthesized landing). Root-level `.md` is allowed here — the "no `.md` at root"
rule is managed-Folio only.

Browse mode is **backend-agnostic**: it runs over any `StorageBackend`, so the
same reader serves local folders, cloud folders (OneDrive/WebDAV, read directly),
and Android's Storage Access Framework (a user-granted `content://` tree). Because
a browsed image may have no `dart:io` path, embedded images render **through the
backend** (`readNoteImage` → `Image.memory`, memoized) so `![](pic.png)` works
everywhere; a Git-LFS pointer stub renders an actionable hint instead of a broken
image.

The **git-read companion** (Android) closes the "keep the folder current" gap
that is otherwise an external sync tool's job: JGit clones a repo into app
storage (materializing LFS via the batch API, authenticating once with a PAT held
in the keystore), Refresh does a pull, and the checked-out working tree is
browsed read-only like any local folder. Read-only by design — Margin stays the
reader, and committing is left to other tools — which preserves the dumb-folder
identity. (JGit is JVM-only, hence Android-only; desktop already has a real
`git`.)

## Encryption (future, post-v1)

Encryption is planned for untrusted backends (notably cloud storage) but
deferred. The important decision now is to leave a clean seam for it.

Encryption is opt-in, per-repository. The default stays plaintext, preserving
the "plain files, readable by any tool" principle. An encrypted repository
trades that browsability for confidentiality from the storage provider.

### Architectural seam to build now

A codec layer sits between the sync engine and the backend:

```
Note model <-> Sync engine <-> [ Codec ] <-> StorageBackend
                                  |
                       identity (default passthrough)
                       encrypt   (opt-in, later)
```

Because the sync engine operates on opaque bytes, it does not care whether those
bytes are plaintext or ciphertext; conflict-copy and push/pull are unaffected.
Building the codec as a no-op passthrough now means adding encryption later is
"implement one more codec," not a rewrite of the sync engine.

### Intended scheme (for later)

- Passphrase -> Argon2id key derivation -> AEAD cipher (XChaCha20-Poly1305 or
  AES-256-GCM), random nonce per file, authenticated to detect tampering.
- The key lives in the OS keystore, keyed by the repository `id`.
- The KDF salt, cipher, and scheme version live in the root `properties.yaml`,
  which stays plaintext (every device needs the recipe to derive the key). It
  holds the recipe, never the key:

```yaml
encryption:
  scheme: xchacha20poly1305
  kdf: argon2id
  salt: <base64>
  version: 1        # algorithm agility for future migration
```

- When encryption is enabled, it covers everything: content, attachments, and
  filenames. If a user opts in, they want full privacy, and encrypting names
  avoids leaking titles and tags. The schema should allow leaving names
  plaintext as an option.
- Search still works: the app decrypts locally and indexes plaintext in memory.
  Only the data at rest on the remote is encrypted.

---

## Local cache and offline (next epic: clone-then-sync)

Non-local Folios (WebDAV, future backends) are **not** operated on live. The
app keeps a local cache and syncs in the background, so notes and attachments
have real on-disk paths (images render, edits work offline on flaky mobile
data), and the existing `SyncEngine`/`SyncPlanner` finally drives sync.

Local layout under the app documents dir:

- `Margin/DeviceNotes/` — the on-device Folio (was `Margin/`; no migration —
  pre-epic local data is disposable).
- `Margin/<UUID>/` — the cache for a remote Folio, keyed by its
  `properties.yaml` id (e.g. `Margin/418f6fbc-…/`).

Open flow (clone-then-sync): on first open, download the remote Folio into its
cache; thereafter the app runs against a `LocalFolderBackend` over the cache,
with the remote (`WebDavBackend`) as the sync peer. A sync indicator shows
state; conflicts surface as conflict copies (already modelled).

Open is **offline-first**: reopening a Folio adopts the on-device cache
immediately and refreshes from the remote in the background (best-effort).
Only the very first open of a never-cached Folio needs a connection — there is
nothing local to fall back to. To locate the cache without first reaching the
remote to identify it, the Folio id is persisted in `SettingsStore`
(`lastFolioId`). This is the whole point of clone-then-sync: a dropped
connection (typical on mobile) must never block opening notes already held.

This is why per-note sidecars and `properties.yaml` matter: they are the
metadata the sync reasons about.

### Sidecar as a search index

The per-note sidecar `<note>.md.yaml` is the note's **lightweight search
index**: `title`, `tags` and `updated` mirror the note's frontmatter, so search
can scan these tiny files instead of opening (and decoding) every `.md`.
`saveNote` rewrites the index in the same operation that writes the note, so the
two never drift. Index fields are metadata only — no body excerpt: a note may be
just pasted URLs or scratch text, where an excerpt carries little meaning. (A
future, opt-in "summarize with Claude" could fill a real summary field; out of
scope now.)

The sidecar also still holds the per-note `view` (editor/split/preview). It is
arguably device-local, but for now it stays in the (synced) sidecar so a
"fully rendered" preference on read-only notes can be evaluated in real use;
revisit moving it to device-local `SettingsStore` after testing.

Hygiene (verified by tests): the sidecar tracks its note — written on
create/save, `view` preserved across content saves, deleted with the note (no
orphan), and moved with the note when its folder is renamed. There is no
note-rename feature yet; if one is added it must move the sidecar too. Notes
authored by other tools gain an index on their first save in Margin.

Slice breakdown (rough): cache layout + `DeviceNotes` move → download-on-open
into the UUID cache → run on the cache backend → wire `SyncEngine` (cache ⇄
remote) + sync indicator → conflict UI → sidecar hygiene.

### Sync UX (next)

Clone-then-sync now works (download-on-open into the cache, run on the cache,
manual "Sync now", auto-reopen). Remaining UX so users don't lose track of what
has reached the server:

- **Auto-sync after save** on a synced Folio — a background sync triggered after
  a successful save/mutation. Must be failure-tolerant: offline / server-down
  must never block editing or lose data (the local cache is the source of
  truth; sync is best-effort and retried later).
- **Unsynced indicator** — track `hasUnsyncedChanges` (set on mutation when
  `canSync`, cleared on a successful sync) and show a "saved but not synced"
  marker (e.g. `*` by the note title).
- Keep manual **Sync now** as the always-available escape hatch.
- Surface sync errors non-blockingly (a dismissible banner/indicator, not a
  hard failure).

### Emptying guard (data safety)

A flaky or incomplete connection can make a side's listing come back empty.
Naively, sync would then read that as "everything was deleted" and propagate a
wipe to the other side — catastrophic for the user's real data. So the engine
**withholds** any plan whose result would be *empty* (everything gone, reached
via deletions) when the base had content: nothing is applied, and
`SyncResult.withheld` is set. The UI shows a non-blocking banner — "This Folio
now looks empty. Sync anyway?" — and only an explicit confirm
(`allowEmptying`) lets the wipe through. The first clone (empty base) and
partial changes (the result still holds files) are never affected. This also
politely double-checks a *genuine* "delete everything", which is rare and
high-stakes. Partial-corruption (a listing missing some files) is not yet
guarded — a possible future "deletes > N%" heuristic.

### Empty-folder hygiene

Deleting a note never removes its containing directory, and sync only moves
files, so editing a Folio's folder directly (e.g. deleting notes in the OS file
manager) can leave empty directories behind. Two safeguards: the tree **hides**
a non-root directory that is neither marked (`properties.yaml`) nor holds a note
(so intentional empty folders and foreign markdown folders still show), and
`ContentService.pruneEmptyFolders()` **removes** recursively-empty directories
from the working backend (run on open and after sync). A directory holding any
file — including its `properties.yaml` marker — is never pruned, so folders you
created on purpose survive even when empty.

## Backlog

The to-do list — everything not built yet — lives in **`BACKLOG.md`** (with
instructions for maintaining it). This file keeps the architecture and rationale.
