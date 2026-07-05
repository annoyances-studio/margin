# BACKLOG.md — Margin

The single to-do list for Margin. **Architecture and rationale live in
`DESIGN.md`; the practical "how to work here" lives in `CLAUDE.md`; the list of
what's *not done yet* lives here.**

## How to use this file

- **One item = one bullet**, imperative, with enough context (files, why) to act
  on later without re-deriving the discussion.
- **Adding:** when the user says "backlog this" / "park that", drop a bullet in
  the most fitting section. A new section is fine if nothing fits.
- **Finishing:** when an item ships, **delete its bullet in the same change**
  (git history is the record). Don't let the list accumulate done items.
- **Parking:** prefix with `[parked]` and a one-line reason when something is
  deliberately deferred (revisit only if a real need appears).
- **Larger/structural** efforts are grouped at the top of their section or
  tagged `[larger]`; small polish sits lower.
- Keep it lean. If a bullet needs a paragraph, the depth belongs in `DESIGN.md`
  with a one-line pointer here.

---

## Backends & sync

- `[larger]` **SFTP/SSH backend** — the main missing backend (local folder,
  WebDAV, and the OneDrive prototype cloud are shipped). Password + SSH-key auth
  via `dartssh2`, behind the same `StorageBackend` interface.
- `[larger]` **Implement conflict surfacing & resolution** — the design is
  written in `DESIGN.md` (Conflict handling → Surfacing & resolution): automatic
  keep-both, a tree-derived cue (AppBar tint + count/row badges), filename-suffix
  marker, Delete/Rename as the whole resolution story, desktop diff/compare view.
  Depends on **note Rename** (below).
- **Live tree refresh / file-watching** — the auto version of the manual Refresh
  button: watch the open folder and reload on external change (debounced,
  cross-platform). Companion mode is the main beneficiary (Claude writes while
  you read).
- **Attachments "clean up unused" scan** — per-folder `_attachments/` is in
  place; a scan to remove files no note references is still to do.
- `[larger]` **Further mobile cloud providers** (Google Drive, Dropbox) — a
  per-provider effort over OAuth + provider REST, still built-in (no plugins).

## Companion mode (read-only plain-folder browsing) — mobile

Companion mode ships on desktop. Making it work on **mobile** is an *access*
gap, not a logic gap (the browse logic is platform-agnostic; mobile can't reach
arbitrary folders via `dart:io`).

- Cloud browse is shipped (OneDrive + WebDAV, via the "Browse read-only" toggle
  in each connect dialog; reads directly, no clone/sync). Follow-ups: the
  OneDrive **in-app folder browser** (below) would make picking a folder to
  browse easier than typing a path; and recursive tree listing over Graph is one
  API call per folder — fine for now, optimize if big trees feel slow.
- **Render embedded images through the backend** — the preview resolves images
  to a local file path (`_imageBaseDir` → `localAbsolutePath`), so `![](pic.png)`
  in a note **doesn't render when browsing a remote (or future zip) folder**
  (no file on disk). Read the bytes via the backend and use `Image.memory`
  (cached) when there's no local path. Prerequisite for great remote/bundle
  reading.
- `[larger]` **Android SAF / document-picker + content-URI backend** — to browse
  a *local* Android folder shared into the app. A different access model than
  the `dart:io`-based `LocalFolderBackend`; Android-specific and bigger.

## Editor & viewing

- **Quick word-wrap toggle** in the editor toolbar (not just Settings), for
  flipping it per-note while reading wide tables.
- `[parked]` **Editable table grid** — pipe coloring + word-wrap-off covers the
  table pain well in daily use; revisit only if a real need appears.
- **Ctrl+Scroll zoom (desktop)** — live text scaling (a settings-persisted scale
  factor at the `MaterialApp` level). Pairs with a denser default.
- **Denser desktop typography** — the overall font may be a touch large on
  desktop; try a slightly denser scale (keep mobile as is). Pairs with zoom.
- **Editor styling** for links `[text](url)`, list bullets, and task checkboxes
  (headings/bold/quotes/table-pipes already styled).
- **Bare-image paste on macOS/Linux/iOS** — `readImage()` is implemented for
  Android (method channel) and Windows (CF_DIB/PNG); other platforms return null
  and fall back to text.
- **Paste fidelity** — HTML/RTF → Markdown fidelity, and formatted paste on
  non-Windows platforms (currently plain text off-Windows).

## Tree & navigation

- **Note Rename** action (context menu) — must move the `.md.yaml` sidecar with
  the note. Prerequisite for conflict resolution.
- `[larger]` **Move / copy notes & folders** — drag-to-move, Ctrl-drag-to-
  duplicate on desktop; carry sidecars and folder markers. Mobile: a "Move to…"
  menu instead of drag.
- **Tree sort & ordering** — name vs. `updated` sort (the sidecar indexes
  `updated`), folders-first, and persisted expand/collapse state.
- **Widen the folder right-click hit area** to the whole row (currently the
  label only).
- **Resizable tree panel** — a draggable divider to set sidebar width (clamped
  min/max), persisted like other device-local prefs.

## Landing & UX

- **Consolidated open/connect button** on the landing, and a rethought **New
  Folio** flow (today a local-only Create button; remote Folios are created
  implicitly through connect). (Recent Folios list — done.)
- **OneDrive in-app folder browser** — the connect dialog takes a typed folder
  path; replace with a visual picker over the Graph API (list/navigate/create).
  Could later serve WebDAV too. (Related to mobile-cloud-browse above.)
- **Hide the search bar until settled** — was cumbersome as filename-only.
  NOTE: browse mode now has deep/full-text search, so **reconsider** rather than
  hide; decide the managed-Folio search story (index scope, ranking).

## Theming & cosmetic

- `[larger]` **Configurable colors / editable themes** — the editor accents
  (links blue, table pipes orange) are hardcoded; expose them via a user-editable
  theme. Includes a **theme-mode switch** (System / Dark / Light) instead of
  always following the OS, and optional **per-Folio `theme.yaml`** so different
  Folios carry different accent colors as a "which Folio am I in" cue.
- Mirror the open note's **breadcrumb into the OS window title** (currently just
  "Margin"); smaller breadcrumb font in the app bar.
- Move the folder **expand/collapse chevron to the left** of the name (less busy,
  symmetric) rather than beside the ⋮ menu.
- **Dragged-file label** — dragged attachments insert `![]()` / `[name]()`; give
  them a `[Dragged File]` label for parity with `[Pasted Image]`. (Collision-
  safety already handled by `addAttachment` de-duplication.)

## Reader & distribution (ideas)

Both fit the existing seams cleanly — browse mode is already the reader, and
`StorageBackend` is already the extension point.

- **Zip / archive container backend** — a read-only `StorageBackend` over a
  `.zip` of plain Markdown (via `package:archive`), opened by browse mode. Lets
  docs ship as one portable, versionable file instead of a loose folder — still
  no proprietary format, just a zip of `.md`. Read-only fits browse mode exactly.
  Depends on **render images through the backend** (above), since bundled images
  aren't files on disk. Could pair with an **export** ("publish this folder as a
  `.md` bundle") for the app-ships-help use case.
- **Light read-only reader build** — a slim build/flavor that compiles out
  editing, sync, and the cloud backends, leaving just "open a folder (or bundle)
  and read." A drop-in **help/documentation viewer other apps could embed or
  point users at** (docs-as-Markdown). Positioning: Margin-the-editor vs
  Margin-the-reader from one codebase.

## Platform, release & CI

See also the `release-roadmap` memory.

- `[larger]` **GitHub CI for builds** — matrix on hosted runners (windows +
  ubuntu-for-APK + macos-for-iOS). The path to an **iOS build**. OneDrive
  `--dart-define`s go in as (public) workflow vars.
- **Release keystore decision** (Android) — release APKs are debug-signed on
  purpose for the Entra/OneDrive signature hash; Play needs a real key (re-
  register its SHA in Entra, or use Play App Signing). Also gates CI signing.
- **Google Play publishing** (first target) — needs the keystore above + an AAB.
- **Windows distribution** — leaning GitHub Releases over the Microsoft Store to
  start.
- **Mobile layout polish** — slide-over tree and the Android/iOS build hardening.
- **Verify macOS + Linux desktop builds** — scaffolding now exists (`flutter
  create`, binary `margin`, id `com.lordofthedummies.margin`), but neither has
  been built; both need their OS or a CI runner. CI can also collect all
  platforms' outputs into a uniform `dist/` (the per-platform build paths differ;
  see CLAUDE.md).
- **macOS file access under App Sandbox** — the generated macOS runner enables
  App Sandbox, which blocks reading arbitrary folders (companion mode's whole
  point). For direct distribution, relax the sandbox entitlement; for the App
  Store, use security-scoped bookmarks (same family as the iOS document-picker
  problem).
