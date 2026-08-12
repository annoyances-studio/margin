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
- **Render embedded images through the backend — SHIPPED.** When the preview has
  no local file path (browsing a remote/SAF folder), it reads the image bytes via
  the backend (`AppController.readNoteImage` → `content.backend.read`, resolved
  relative to the open note, root-escape guarded) and renders `Image.memory`,
  memoized per src (no re-read/flicker). Local Folios still use the fast
  `Image.file` path. Unblocks remote + SAF + future-zip image reading. Follow-ups
  if needed: a size cap / eviction on the in-memory cache for image-heavy notes,
  and a shared cache across notes (currently per-preview, reset on note switch).
- **Android SAF companion — SHIPPED.** The user picks a folder via the system
  picker (SAF); a read-only `SafBackend` over a Kotlin method channel reads the
  granted `content://` tree (`DocumentFile`); recent-folios stores the URI for
  one-tap reopen; browsed notes open in Preview and Android Back walks note
  history. Remaining follow-ups: **render images through the backend** (above —
  SAF has no `dart:io` path, so `![](pic.png)` doesn't render yet); and the
  path→document resolution uses `findFile` per segment (O(children) per level) —
  if big trees feel slow, construct document URIs directly (`DocumentsContract`).
  LEARNED: another app's `Android/data/<pkg>/` (e.g. an MGit clone) is
  unreachable by SAF *and* `MANAGE_EXTERNAL_STORAGE` on Android 11+ — the folder
  must live in **shared** storage (Documents/Downloads, a Syncthing/cloud folder,
  or a Termux clone under `~/storage/shared`).

- `[larger]` `[idea]` **Git-read backend (pull-only, no push)** — a *separate,
  walled-off* idea from SAF: a backend that clones/pulls a repo directly and
  browses it read-only, so the folder-freshness problem is solved inside Margin
  instead of by an external sync tool. Would need a bundled Dart git
  implementation (`dart_git`/libgit2-style — no shell inside the Android
  sandbox). Overlaps with GitJournal; kept out of the SAF path so it can't
  complicate it. Lower priority — the in-philosophy answer is "read a folder
  someone else syncs."
  - **Why it would actually be worth building (the value prop):** kill the
    mobile-git *auth* annoyance. Every mobile git tool (MGit, Termux) makes you
    fight PAT/SSH-key entry per clone. Margin could take a PAT **once**, store it
    in the OS keystore via the existing `CredentialStore` (same as WebDAV/OneDrive
    creds), and never re-prompt. "The markdown reader that makes mobile-git-auth
    a one-time thing" is the differentiator, not "it does git."
  - **The scope-creep trap to decide up front:** cloning into Margin's *own*
    managed folder is simpler than SAF (known location, no picker) — BUT once a
    repo lives in Margin's folder, users will expect a *proper* git backend
    (commit/push), not read-only. Desktop dodges this because the folder is "just
    a folder that happens to be git," and external git tools do the committing;
    mobile has no such tool, so the expectation lands squarely on Margin. So the
    boundary must be chosen deliberately: stay a pull-only reader, or accept
    becoming a git client. Staying read-only keeps the "dumb folder" identity.
  - **Resolution to the trap (from MGit testing):** clone into a **shared-storage**
    managed folder (not app-private), so any external tool can commit/push against
    it — Margin stays the read-only reader, the folder is "just a folder that
    happens to be git," and the desktop model is preserved on mobile. Bonus: a
    shared, well-known folder could one day be operated on by *other apps,
    possibly the Claude App itself*. (Contrast: cloning into app-private storage
    is where the "must become a git client" pressure comes from.)
  - **Auth, kept simple (from MGit testing):** a single **username + password**
    field covers most git servers over HTTPS; for GitHub the "password" is just a
    **PAT**. So v1 needs no SSH-key UI — one username + one password/PAT field,
    stored in `CredentialStore`. (Public repos need no auth at all.)
  - **Git LFS is another external-client gap (from MGit testing):** MGit clones
    LFS-tracked files as ~130-byte pointer stubs (not the binary), so images
    silently don't render — Margin reads the stub faithfully, it's just not an
    image. A controlled git-read backend could handle/`git lfs pull` (or at least
    detect it), which external clients get wrong. One more "control the clone"
    argument. Interim fix is the sync layer's job (Termux `git lfs pull`,
    Syncthing/cloud).

- **Detect a Git LFS pointer in the preview and show a hint** — small, standalone
  win independent of the git-read backend. When an image's bytes are a Git LFS
  pointer (a small text file starting with
  `version https://git-lfs.github.com/spec/v1`), the preview currently shows a
  generic broken-image icon. Detect that signature (in `readNoteImage` or the
  image widget) and render an actionable message instead ("Git LFS pointer — run
  `git lfs pull`") so the user isn't left guessing.

## Editor & viewing

- **Line-number gutter (editor)** — optional companion to the shipped go-to-line
  (Ctrl+G): a toggleable left gutter numbering source lines, so a line Claude
  cites is visible without jumping. Deferred for the pixel-alignment work (the
  gutter must track the field's wrapped-line Y exactly — same TextPainter
  machinery as find's reveal, but a gutter is stared at so drift shows). Desktop,
  opt-in.
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

## Editor & viewing (continued)

- **Find-in-note follow-ups.** Ctrl+F find shipped on desktop (one engine over
  the note text: editor/split highlight all matches + reveal the active one;
  preview highlights the active match in place — a sentinel-wrapped `mark`
  element via a custom inline syntax/builder — and scrolls it exactly into view;
  case toggle; Enter/Shift+Enter/Esc; a view-mode change resets find). Still to do:
  - **Mobile entry point** — no Ctrl+F on phones; add a find affordance and
    coordinate across the separate editor/preview pages (find lives in the
    desktop `NoteEditorPane`, which the phone layout doesn't use for preview).
  - **Preview highlight edge cases** — inline code spans ARE highlighted (custom
    `code` builder), but injection is still skipped (match counts, no
    highlight/scroll) when it crosses a line/block boundary or sits inside a
    ``` fenced block (rendered on a separate scrollable path). Only the *active*
    match is highlighted in preview (the editor shows all). Preview uses
    `MarkdownBody` in an owned scroll view so every block is built and any match
    can be revealed — revisit if huge notes feel slow (loses list virtualization).
  - Optional niceties: whole-word / regex, and replace.

## Tree & navigation

- **Back/forward follow-ups** — history nav shipped on desktop (app-bar arrows,
  browser-style stack over opened notes; cleared per Folio, prunes deleted
  paths). To do: a **mobile entry point** (the phone bar is crowded; Android
  system Back currently backgrounds the app), and maybe keyboard shortcuts
  (Alt+←/→) + mouse back/forward buttons.
- **Preview link destination** — hovering a preview link shows its destination
  in a bottom status strip and switches to a click cursor. Implemented WITHOUT a
  custom `a` builder on purpose: registering one leaves flutter_markdown's link
  handler unpopped (its pop is in an `else if` skipped when a builder exists),
  so the stale recognizer attaches to all following text — clicking plain text
  then navigates. So links render natively (correct taps/flow) and hover is
  resolved by hit-testing the rendered paragraphs for a link span, mapping its
  text back to the source href. Follow-ups: hit-test runs on pointer move
  (throttled ~4px) — watch perf on huge notes; href lookup is by link *text*, so
  two links with identical text resolve to the first; and a find match inside
  link text still isn't highlighted.
- **Note Rename** action (context menu) — must move the `.md.yaml` sidecar with
  the note. Prerequisite for conflict resolution.
- `[larger]` **Move / copy notes & folders** — drag-to-move, Ctrl-drag-to-
  duplicate on desktop; carry sidecars and folder markers. Mobile: a "Move to…"
  menu instead of drag.
- **Tree sort & ordering** — name vs. `updated` sort (the sidecar indexes
  `updated`), folders-first. (Collapse/expand-all shipped via a central
  expansion model in `FolderTreeView`; **persisting** that expand/collapse state
  across sessions is the remaining piece — the model is now there to hang it on.)
- **Widen the folder right-click hit area** to the whole row (currently the
  label only).
- **Persist the sidebar width** — the tree panel is now drag-resizable (clamped
  min/max), but the width resets each launch; persist it like other device-local
  prefs (settings store + AppController), alongside the expand/collapse state.

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
- **Move Margin to `studio.annoyances.margin` before first Play upload.** Studio
  brand is decided — **Annoyances Studio** (domain `annoyances.studio`), namespace
  `studio.annoyances.*`. Margin currently ships `com.lordofthedummies.margin` and
  isn't on Play yet, so the id can still change (permanent after first upload).
  **Batch the change with the keystore + Entra pass below** — both the new package
  and the new signing hash rewrite the OneDrive redirect URI `msauth://<pkg>/<hash>`,
  so do them together (one Entra reconfig). Package id is invisible to users (they
  see "Margin•").
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
