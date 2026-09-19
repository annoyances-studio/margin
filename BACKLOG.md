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

## Companion mode (read-only plain-folder browsing)

Shipped across desktop, cloud (OneDrive/WebDAV "Browse read-only", read
directly), and Android (SAF folder pick + the git-read backend below). Embedded
images render **through the backend** (`readNoteImage` → `Image.memory`, memoized)
so `![](pic.png)` works where there's no `dart:io` path; a Git-LFS pointer stub
shows an actionable hint instead of a broken image. Remaining follow-ups:

- **OneDrive in-app folder browser** — picking a browse folder still means typing
  a path; a visual Graph picker (see Landing & UX) would help. Recursive tree
  listing over Graph is one API call per folder — fine for now.
- **Image cache tuning** — the per-preview image cache resets on note switch; add
  a size cap / eviction and a cache shared across notes if image-heavy notes feel
  heavy.
- **SAF path resolution** — `SafBackend` builds document URIs directly
  (`DocumentsContract`) with a `findFile` fallback; fine in practice. LEARNED: a
  browsed folder must live in **shared** storage — another app's
  `Android/data/<pkg>/` (e.g. an MGit clone) is unreachable by SAF *and*
  `MANAGE_EXTERNAL_STORAGE` on Android 11+.

### Git-read backend — SHIPPED (Android), read-only

Clone/pull a repo directly and browse it read-only, so folder-freshness is solved
inside Margin instead of by an external sync tool (on-device git tools are
inadequate — MGit clones LFS as pointer stubs; Termux is impractical). Shipped:
**JGit** behind the `margin/app` method channel clones into app storage and Margin
browses the working tree via `LocalFolderBackend` — git *materializes*, it does
not *read*, so there's no new backend and images hit the local-file fast path.
**Git-LFS** blobs are fetched via the batch API and the pointer stubs overwritten
(JGit's checkout leaves pointers). **Auth once** — username + PAT in the keystore
(`CredentialStore`), offline-first reopen from the local clone. **Refresh = pull**
(fetch + hard-reset + re-LFS), best-effort: a failed pull keeps the last-good
clone and warns. Read-only by design preserves the dumb-folder identity (Margin
reads; committing is another tool's job). JGit is JVM-only, hence Android-only.
Remaining:
- `[larger]` **Shared-storage destination** — the clone lands in app-*private*
  storage today, invisible to Android's file explorer and other apps
  (field-reported). Move it to **shared** storage (and let the user pick a root),
  making it "just a folder that happens to be git" that other tools — possibly the
  Claude app — could operate on. The identity-defining follow-up.
- **LFS object caching** — each pull re-downloads all LFS blobs (the reset reverts
  them to pointers; we don't populate `.git/lfs/objects`). Cache objects to skip
  the re-download.
- **Desktop** — not offered; desktop already has a real `git` (would shell out).
- Always a **full clone/pull** (no sparse fetch): notes link to siblings/assets,
  and we won't parse them to decide what to pull. (Decided.)

## Editor & viewing

- **Find & replace (Edit mode)** — extend the shipped Ctrl+F find engine with a
  replace field (replace / replace-all), Edit/Split only. Reuse the find match
  model; add the replace UI to `note_editor_pane.dart`'s find session.
- **Text tools: natural (numeric) line sort** — the shipped right-click *Sort
  lines* is plain case-insensitive alphabetical, so `10` sorts before `2`. Add a
  numeric/natural-sort variant (parse leading numbers, natural-compare). More
  involved than the pure string ops; a follow-up to the shipped text-transforms
  menu in `text_transforms.dart`.
- **Line-number gutter (editor)** — optional companion to the shipped go-to-line
  (Ctrl+G): a toggleable left gutter numbering source lines, so a line Claude
  cites is visible without jumping. Deferred for the pixel-alignment work (the
  gutter must track the field's wrapped-line Y exactly — same TextPainter
  machinery as find's reveal, but a gutter is stared at so drift shows). Desktop,
  opt-in.
- **Image sizing (plain-text width hint)** — no way to resize an embedded image
  yet (the one thing missed vs OneNote). Must stay **plain-text** so the folder
  stays portable: honor a width hint written into the Markdown that degrades
  gracefully everywhere else. Obsidian's `![alt|300](path)` (or `|300x200`) is the
  common convention — GitHub and others still render the image, just with the
  literal alt text. The preview already has a custom image builder
  (`markdown_preview.dart` `_buildImage` / `sizedImageBuilder`), so v1 = parse a
  trailing `|W[xH]` in the alt and set the widget width/height. Nicer later: a way
  to set it (right-click an image → set width, or drag-handles in the preview)
  that writes the suffix back into the note text.
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

- **View-mode control is ~4px taller than the search box** (title bar). Material's
  `SegmentedButton` keeps a minimum segment height that `maximumSize`/`minimumSize`
  don't override, so it overshoots the search field by ~2px top and bottom. Small;
  fix by wrapping in a tight `SizedBox`/`FittedBox` or a custom segmented control.

- `[larger]` **Configurable colors / editable themes** — the editor accents
  (links blue, table pipes orange) are hardcoded; expose them via a user-editable
  theme. Includes a **theme-mode switch** (System / Dark / Light) instead of
  always following the OS, and optional **per-Folio `theme.yaml`** so different
  Folios carry different accent colors as a "which Folio am I in" cue.
- **App mark → window system menu (desktop).** Make the top-left Margin mark a
  touch smaller and, on click, open a menu of window commands — Restore /
  Move / Size / Minimize / Maximize (the standard Windows system menu, custom-
  drawn), plus **Always on top** and **Close Margin**. This is the home for the
  window-level actions currently scattered in the overflow ⋮.
- **Neaten the title-bar overflow ⋮ (desktop).** Once the app-mark menu exists,
  the desktop ⋮ should hold just **Settings** — Always-on-top and Close Margin
  move to the app-mark menu, Close folio is already on the folio switcher. Mobile
  keeps its fuller overflow (no app-mark menu there).
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

See also the `release-roadmap` memory. **Done:** package migration to
`studio.annoyances.margin`; the **upload keystore** (signed release, SHA
registered in Entra for OneDrive); **Android developer verification** (package
registered); and **CI for Windows + Android** — a `v*` tag builds a signed
Android APK + a Windows zip and attaches both to the GitHub Release (Android
signing is gated by the `android-release` Environment, which enforces a required
reviewer once the repo is public). Off-store distribution via GitHub Releases.
Remaining:

- **CI for macOS + iOS** — add those runners (macOS is the path to the **iOS
  build**), and collect every platform's output into a uniform `dist/` (the
  per-platform build paths differ; see CLAUDE.md).
- **Google Play publishing** — needs an **AAB** (CI builds APK only today) plus
  the listing. Play / Obtainium / F-Droid all optional; off-store is the default.
- **Verify macOS + Linux desktop builds** — scaffolding exists (`flutter create`,
  binary `margin`), but neither has been built; each needs its OS or a CI runner.
- **macOS file access under App Sandbox** — the generated macOS runner enables App
  Sandbox, which blocks reading arbitrary folders (companion mode's whole point).
  Direct distribution: relax the entitlement; App Store: security-scoped bookmarks
  (same family as the iOS document-picker problem).
- **Mobile layout polish** — slide-over tree and Android/iOS build hardening.
