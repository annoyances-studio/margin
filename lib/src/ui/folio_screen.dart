// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../content/tree_node.dart';
import '../desktop/desktop_integration.dart';
import '../desktop/file_reveal.dart';
import '../desktop/startup_service.dart';
import 'app_controller.dart';
import 'color_hex.dart';
import 'settings_dialog.dart';
import 'widgets/attach_drop_target.dart';
import 'widgets/folder_tree.dart';
import 'widgets/markdown_preview.dart';
import 'widgets/note_editor_pane.dart';

/// The two-panel desktop layout (DESIGN.md): a collapsible folder tree on the
/// left, the note editor on the right.
class FolioScreen extends StatefulWidget {
  final AppController controller;
  final StartupService startupService;

  const FolioScreen({
    super.key,
    required this.controller,
    this.startupService = const NoopStartupService(),
  });

  @override
  State<FolioScreen> createState() => _FolioScreenState();
}

class _FolioScreenState extends State<FolioScreen> {
  /// Breakpoint below which the phone (drawer) layout is used.
  static const double _wideBreakpoint = 720;

  bool _showTree = true;

  /// Last title pushed to the OS window, to avoid redundant native calls.
  String? _lastWinTitle;

  /// The editor's current caret line/column, shown in the desktop status bar.
  /// A notifier so only the status-bar text rebuilds as the caret moves.
  final ValueNotifier<({int line, int col})?> _caret = ValueNotifier(null);

  /// Desktop sidebar width, adjustable by dragging the divider (clamped).
  double _treeWidth = 280;
  static const double _minTreeWidth = 180;
  static const double _maxTreeWidth = 520;

  // Phone layout: three swipeable pages (0 folders, 1 editor, 2 preview).
  final PageController _pageController = PageController(initialPage: 1);
  int _currentPage = 1;

  /// Whether the last build used the wide layout, to detect a layout switch
  /// (rotation/resize) and carry the editor-vs-preview choice across it.
  bool? _wasWide;

  final TextEditingController _searchController = TextEditingController();

  AppController get controller => widget.controller;

  /// Localized strings for the current context.
  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    // Reapply the persisted always-on-top preference to the window on launch.
    if (controller.alwaysOnTop) setWindowAlwaysOnTop(true);
  }

  @override
  void dispose() {
    _caret.dispose();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Keeps editor-vs-preview consistent when the layout flips (rotation/resize).
  /// Into wide: adopt the pager's page as the view mode. Into narrow: open the
  /// pager on the page matching the view mode. The folders page (0) is left
  /// alone — it's navigation, not a view mode.
  void _syncViewAcrossLayout(bool toWide) {
    if (!mounted) return;
    if (toWide) {
      if (_currentPage == 2) {
        controller.setViewMode(EditorViewMode.preview);
      } else if (_currentPage == 1) {
        controller.setViewMode(EditorViewMode.edit);
      }
    } else if (_pageController.hasClients) {
      _pageController.jumpToPage(
        controller.viewMode == EditorViewMode.preview ? 2 : 1,
      );
    }
  }

  void _openSettings() => SettingsDialog.show(
        context,
        startupService: widget.startupService,
        controller: controller,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideBreakpoint;
            final firstBuild = _wasWide == null;
            final switched = !firstBuild && _wasWide != wide;
            _wasWide = wide;
            // Keep the swipe-pager's page and the wide view mode consistent:
            // - on a layout flip (rotation/resize), carry the choice across;
            // - on the first narrow build, open on the page matching the view
            //   mode, so a browsed folder (which resolves to preview) opens
            //   rendered rather than on the raw editor page.
            if (switched) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _syncViewAcrossLayout(wide));
            } else if (firstBuild && !wide) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _syncViewAcrossLayout(false));
            }
            return wide
                ? _buildWide(context)
                : _buildNarrow(context);
          },
        );
      },
    );
  }

  // --- wide (desktop) layout: tree panel + editor, with view-mode control ---

  Widget _buildWide(BuildContext context) {
    // Push the open document's name to the OS window title (taskbar / alt-tab).
    final winTitle = _documentName();
    if (winTitle != _lastWinTitle) {
      _lastWinTitle = winTitle;
      unawaited(setWindowTitle(winTitle));
    }
    return Scaffold(
      appBar: _desktopTitleBar(),
      body: Column(
        children: [
          _accentDivider(),
          if (controller.error != null) _errorBanner(controller.error!),
          if (controller.syncNeedsEmptyConfirm) _emptySyncBanner(),
          Expanded(child: _wideContent()),
          _statusBar(),
        ],
      ),
    );
  }

  /// Margin's merged title bar (desktop): the OS chrome is hidden, so this one
  /// strip carries the app mark, folders/history controls, the document name (a
  /// draggable region), the view-mode control and menu, and — on Windows/Linux —
  /// the window buttons. macOS keeps its native traffic-lights at the left, and
  /// the Margin mark moves to the right so the left isn't crowded.
  PreferredSizeWidget _desktopTitleBar() {
    final scheme = Theme.of(context).colorScheme;
    final onMac = isMacOSDesktop;
    final showOwnButtons = isDesktop && !onMac;

    final crumb = _titleBreadcrumb();

    return PreferredSize(
      preferredSize: const Size.fromHeight(46),
      child: Material(
        color: scheme.surfaceContainer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  // macOS: leave room for the native traffic-lights; else the mark.
                  if (onMac) const SizedBox(width: 72) else _appMark(),
                  IconButton(
                    tooltip: _showTree ? _l10n.hideFolders : _l10n.showFolders,
                    icon: Icon(_showTree ? Icons.menu_open : Icons.menu),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _showTree = !_showTree),
                  ),
                  IconButton(
                    tooltip: _l10n.navigateBack,
                    icon: const Icon(Icons.arrow_back),
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        controller.canGoBack ? () => controller.goBack() : null,
                  ),
                  IconButton(
                    tooltip: _l10n.navigateForward,
                    icon: const Icon(Icons.arrow_forward),
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.canGoForward
                        ? () => controller.goForward()
                        : null,
                  ),
                  IconButton(
                    tooltip: controller.isGitFolio
                        ? _l10n.pullLatest
                        : _l10n.refreshTree,
                    icon: const Icon(Icons.refresh),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.refreshTree(),
                  ),
                  Expanded(
                    flex: 3,
                    child: isDesktop ? DragToMoveArea(child: crumb) : crumb,
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _titleSearch(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _viewModeControl(),
                  ),
                  if (controller.selectedNotePath != null)
                    IconButton(
                      tooltip: _l10n.backlinks,
                      icon: const Icon(Icons.hub_outlined),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showBacklinks(context),
                    ),
                  if (controller.selectedNotePath != null &&
                      !controller.isBrowsing)
                    IconButton(
                      tooltip: _l10n.attachFile,
                      icon: const Icon(Icons.attach_file),
                      visualDensity: VisualDensity.compact,
                      onPressed: _attachFile,
                    ),
                  if (!controller.isBrowsing) _saveAction(),
                  if (controller.syncError != null) _syncRetryAction(),
                  _overflowMenu(),
                  if (onMac) _appMark(),
                  if (showOwnButtons) const _WindowButtons(),
                ],
              ),
            ),
            if (controller.isBusy) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  Widget _appMark() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CustomPaint(
            painter: _MarginMarkPainter(Theme.of(context).colorScheme.primary),
          ),
        ),
      );

  /// The breadcrumb shown in the title bar's drag region: the open note's folder
  /// path and name (folio name when none is open). Non-interactive so the region
  /// stays draggable. The literal full path lives in the status bar.
  Widget _titleBreadcrumb() {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: scheme.onSurfaceVariant);
    final strong = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600);
    final notePath = controller.selectedNotePath;
    final spans = <InlineSpan>[];
    if (notePath == null) {
      spans.add(TextSpan(text: controller.folioName, style: strong));
    } else {
      final parts = notePath.split('/');
      final file = parts.removeLast();
      final name = file.toLowerCase().endsWith('.md')
          ? file.substring(0, file.length - 3)
          : file;
      for (final folder in parts) {
        spans.add(TextSpan(text: folder, style: muted));
        spans.add(TextSpan(text: '  ›  ', style: muted));
      }
      spans.add(TextSpan(text: name, style: strong));
    }
    return Container(
      alignment: Alignment.centerLeft,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// The note search field, hosted in the title bar on desktop (results still
  /// render in the tree). Shares [_searchController] with the mobile field.
  Widget _titleSearch() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: TextField(
        controller: _searchController,
        onChanged: controller.setSearchQuery,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          hintText: _l10n.searchNotes,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixIcon: controller.isSearching
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: _l10n.cancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _searchController.clear();
                    controller.clearSearch();
                  },
                )
              : null,
        ),
      ),
    );
  }

  /// The open document's display name for the OS window title (taskbar /
  /// alt-tab): the note name without `.md`; a top-level README shows its
  /// folder's name; no note open falls back to the Folio name.
  String _documentName() {
    final notePath = controller.selectedNotePath;
    if (notePath == null) return '${controller.folioName}$_unsyncedMark';
    final slash = notePath.lastIndexOf('/');
    final file = slash < 0 ? notePath : notePath.substring(slash + 1);
    var name =
        file.toLowerCase().endsWith('.md') ? file.substring(0, file.length - 3) : file;
    if (name.toLowerCase() == 'readme') {
      final folder = slash < 0 ? '' : notePath.substring(0, slash);
      final fslash = folder.lastIndexOf('/');
      final fname = fslash < 0 ? folder : folder.substring(fslash + 1);
      if (fname.isNotEmpty) name = fname;
    }
    return '$name$_unsyncedMark';
  }

  /// Bottom status strip: the open note's full path (the canonical "where am I",
  /// freeing the title bar to show just the document name) plus a compact sync
  /// state.
  Widget _statusBar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _wideTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              // Caret line/column — only this text rebuilds as the caret moves.
              ValueListenableBuilder<({int line, int col})?>(
                valueListenable: _caret,
                builder: (context, caret, _) => caret == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text(
                          _l10n.lineColumn(caret.line, caret.col),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                        ),
                      ),
              ),
              if (controller.canSync)
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Icon(
                    controller.syncError != null
                        ? Icons.cloud_off_outlined
                        : (controller.hasUnsyncedChanges
                            ? Icons.cloud_upload_outlined
                            : Icons.cloud_done_outlined),
                    size: 14,
                    color: controller.syncError != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- narrow (phone) layout: editor body, swipe-in tree & preview drawers ---

  Widget _buildNarrow(BuildContext context) {
    return Scaffold(
      // resizeToAvoidBottomInset (default true) lifts the bottom bar above the
      // keyboard.
      body: SafeArea(
        child: Column(
          children: [
            _mobileHeader(),
            _accentDivider(),
            if (controller.error != null) _errorBanner(controller.error!),
            if (controller.syncNeedsEmptyConfirm) _emptySyncBanner(),
            if (controller.isBusy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _mobilePager()),
            _mobileBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _mobileHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _mobileTitle(),
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // A brief cue that the latest version is being fetched on open.
          if (controller.noteRefreshing)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(_l10n.checkingForUpdates,
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
        ],
      ),
    );
  }

  /// Three swipeable pages: folders, editor, preview. Center swipe avoids the
  /// screen edges, so it doesn't fight Android's system back gesture.
  Widget _mobilePager() {
    final tree = controller.tree;
    final notePath = controller.selectedNotePath;
    return PageView(
      controller: _pageController,
      onPageChanged: (i) => setState(() => _currentPage = i),
      children: [
        tree == null
            ? const SizedBox.shrink()
            : _pullToRefresh(
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: _treePanelContent(
                    // Browsed (read-only) folders are for reading, so land on
                    // the rendered preview; editable Folios land on the editor.
                    onNoteSelected: () =>
                        _goToPage(controller.isBrowsing ? 2 : 1),
                    scrollable: true,
                  ),
                ),
              ),
        NoteEditorPane(
          notePath: notePath,
          body: controller.workingBody,
          onChanged: controller.updateBody,
          mode: EditorViewMode.edit, // preview is its own page here
          revision: controller.editorRevision,
          imageBaseDir: _imageBaseDir(),
          imageLoader: controller.readNoteImage,
          onSpecialCopy: controller.canCopyNote ? _showCopyMenu : null,
          onSaveAttachment: controller.saveAttachmentForCurrentNote,
          onDownloadImage: controller.downloadImageAsAttachment,
          wordWrap: controller.wordWrap,
          onToggleWordWrap: () =>
              controller.setWordWrap(!controller.wordWrap),
          readOnly: controller.isBrowsing,
          onOpenLink: controller.openLink,
        ),
        notePath == null
            ? Center(child: Text(_l10n.selectNoteToPreview))
            : _pullToRefresh(
                MarkdownPreview(
                  key: ValueKey('preview:${controller.selectedNotePath}'),
                  data: controller.workingBody,
                  imageBaseDir: _imageBaseDir(),
                  imageLoader: controller.readNoteImage,
                  physics: const AlwaysScrollableScrollPhysics(),
                  onSpecialCopy: controller.canCopyNote ? _showCopyMenu : null,
                  onOpenLink: controller.openLink,
                ),
              ),
      ],
    );
  }

  /// Wraps a scrollable mobile page so a pull-down gesture refreshes — the touch
  /// equivalent of the app-bar ↻ (which the crowded phone bar doesn't show). For
  /// a managed Folio that's "Sync now"; for a git clone it's a pull (fetch +
  /// reset + re-LFS). Other Folios have nothing to fetch, so the child is
  /// returned unchanged.
  Widget _pullToRefresh(Widget child) {
    if (controller.canSync) {
      return RefreshIndicator(
        onRefresh: () => controller.syncNow(),
        child: child,
      );
    }
    if (controller.isGitFolio) {
      return RefreshIndicator(
        onRefresh: () => controller.refreshTree(),
        child: child,
      );
    }
    return child;
  }

  Widget _mobileBottomBar() {
    final hasNote = controller.selectedNotePath != null;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _pageNavButton(0, Icons.folder_outlined, _l10n.folders),
            _pageNavButton(1, Icons.edit_note, _l10n.editor),
            _pageNavButton(2, Icons.visibility_outlined, _l10n.preview),
            const Spacer(),
            IconButton.filled(
              tooltip: _l10n.newNote,
              icon: const Icon(Icons.add),
              onPressed: _promptNewNote,
            ),
            const Spacer(),
            if (hasNote)
              IconButton(
                tooltip: _l10n.attachFile,
                icon: const Icon(Icons.attach_file),
                onPressed: _attachFile,
              ),
            if (hasNote) _saveAction(),
            if (controller.syncError != null) _syncRetryAction(),
            _overflowMenu(),
          ],
        ),
      ),
    );
  }

  Widget _pageNavButton(int index, IconData icon, String tooltip) {
    final selected = _currentPage == index;
    // The active mode is highlighted; inactive ones are dimmed to grey (the
    // same affordance as the disabled Save icon) so the current mode is clear.
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).disabledColor,
      icon: Icon(icon),
      onPressed: () => _goToPage(index),
    );
  }

  // --- shared app-bar actions ---

  Widget _saveAction() => IconButton(
        tooltip: _l10n.save,
        icon: const Icon(Icons.save_outlined),
        onPressed: controller.isDirty ? () => controller.save() : null,
      );

  /// The 3-dot overflow menu, shared by the desktop app bar and the phone
  /// bottom bar: Settings, Close, and (desktop only) an Always-on-top toggle.
  Widget _overflowMenu() => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: _l10n.more,
        onSelected: _handleOverflow,
        itemBuilder: (_) => [
          if (controller.canSync)
            PopupMenuItem(value: 'sync', child: Text(_l10n.syncNow)),
          if (isDesktop)
            CheckedPopupMenuItem(
              value: 'alwaysOnTop',
              checked: controller.alwaysOnTop,
              child: Text(_l10n.alwaysOnTop),
            ),
          PopupMenuItem(value: 'settings', child: Text(_l10n.settings)),
          PopupMenuItem(value: 'close', child: Text(_l10n.closeFolio)),
          // Desktop hides to the tray on window-close; this quits for real.
          if (isDesktop)
            PopupMenuItem(value: 'quit', child: Text(_l10n.closeMargin)),
        ],
      );

  /// Shown when a background sync failed: a tap retries. Non-blocking.
  Widget _syncRetryAction() => IconButton(
        tooltip: controller.syncError,
        icon: Icon(
          Icons.cloud_off_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        onPressed: () => controller.syncNow(),
      );

  void _handleOverflow(String value) {
    switch (value) {
      case 'sync':
        controller.syncNow();
      case 'alwaysOnTop':
        _toggleAlwaysOnTop();
      case 'settings':
        _openSettings();
      case 'close':
        controller.closeFolio();
      case 'quit':
        quitDesktopApp();
    }
  }

  /// Lets the user copy the open note as rich text (for Word/web), Markdown
  /// source, or plain text — the copy half of the clipboard interop.
  Future<void> _showCopyMenu() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = _l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: Text(l10n.copyFormatted),
              onTap: () => Navigator.pop(context, 'formatted'),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(l10n.copyAsMarkdown),
              onTap: () => Navigator.pop(context, 'markdown'),
            ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(l10n.copyAsPlainText),
              onTap: () => Navigator.pop(context, 'plain'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'formatted':
        await controller.copyNoteFormatted();
      case 'markdown':
        await controller.copyNoteMarkdown();
      case 'plain':
        await controller.copyNotePlain();
      default:
        return; // dismissed
    }
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.copiedToClipboard),
      duration: const Duration(seconds: 1),
    ));
  }

  Future<void> _toggleAlwaysOnTop() async {
    final value = !controller.alwaysOnTop;
    await controller.setAlwaysOnTop(value); // persists + notifies (updates check)
    await setWindowAlwaysOnTop(value);
  }

  /// A trailing "*" when there are local changes not yet synced to the remote.
  String get _unsyncedMark => controller.hasUnsyncedChanges ? ' *' : '';

  /// Wide title: Folio name plus the open note's path. Shown even when the tree
  /// is visible — a note inside a collapsed folder is otherwise invisible, so
  /// the breadcrumb is the only reliable "where am I" cue.
  String _wideTitle() {
    final repo = controller.folioName;
    final notePath = controller.selectedNotePath;
    if (notePath != null) {
      return '$repo / ${notePath.replaceAll('/', ' / ')}$_unsyncedMark';
    }
    return '$repo$_unsyncedMark';
  }

  /// Narrow title: the open note's name, or the Folio name.
  String _mobileTitle() {
    final notePath = controller.selectedNotePath;
    if (notePath == null) return '${controller.folioName}$_unsyncedMark';
    final name = notePath.split('/').last;
    final title =
        name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
    return '$title$_unsyncedMark';
  }

  Widget _viewModeControl() {
    return SegmentedButton<EditorViewMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        ButtonSegment(
          value: EditorViewMode.edit,
          icon: const Icon(Icons.edit_note),
          tooltip: _l10n.editor,
        ),
        ButtonSegment(
          value: EditorViewMode.split,
          icon: const Icon(Icons.vertical_split_outlined),
          tooltip: _l10n.splitEditorPreview,
        ),
        ButtonSegment(
          value: EditorViewMode.preview,
          icon: const Icon(Icons.visibility_outlined),
          tooltip: _l10n.preview,
        ),
      ],
      selected: {controller.viewMode},
      onSelectionChanged: (selection) =>
          controller.setViewMode(selection.first),
    );
  }

  Widget _wideContent() {
    final tree = controller.tree;
    final editor = AttachDropTarget(
      enabled: controller.selectedNotePath != null && !controller.isBrowsing,
      onAttach: controller.attachToCurrentNote,
      child: NoteEditorPane(
        notePath: controller.selectedNotePath,
        body: controller.workingBody,
        onChanged: controller.updateBody,
        mode: controller.viewMode,
        revision: controller.editorRevision,
        imageBaseDir: _imageBaseDir(),
        imageLoader: controller.readNoteImage,
        onSpecialCopy: controller.canCopyNote ? _showCopyMenu : null,
        onSaveAttachment: controller.saveAttachmentForCurrentNote,
        onDownloadImage: controller.downloadImageAsAttachment,
        wordWrap: controller.wordWrap,
        onToggleWordWrap: () => controller.setWordWrap(!controller.wordWrap),
        onCaretChanged: (c) => _caret.value = c,
        readOnly: controller.isBrowsing,
        onOpenLink: controller.openLink,
        onNavigateBack: () => controller.goBack(),
      ),
    );

    if (!_showTree || tree == null) {
      return editor;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _treeWidth,
          child: Material(
            // A slightly distinct surface tone sets the sidebar apart from the
            // editor (VS Code / Claude-desktop style).
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            // Search lives in the title bar on desktop, not the tree.
            child: _treePanelContent(includeSearch: false),
          ),
        ),
        _treeResizeHandle(),
        Expanded(child: editor),
      ],
    );
  }

  /// A draggable divider that resizes the sidebar (clamped between a sensible
  /// min and max). A wide hit area over a thin visual line, with a resize
  /// cursor on desktop.
  Widget _treeResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => setState(() {
          _treeWidth =
              (_treeWidth + d.delta.dx).clamp(_minTreeWidth, _maxTreeWidth);
        }),
        child: SizedBox(
          width: 8,
          child: Center(
            child: VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// The folder tree with its header, shared by the desktop side panel and the
  /// phone folders page. [onNoteSelected] fires after a note is tapped (used on
  /// phones to swipe to the editor page).
  Widget _treePanelContent({
    VoidCallback? onNoteSelected,
    bool scrollable = false,
    bool includeSearch = true,
  }) {
    final tree = controller.tree;
    if (tree == null) return const SizedBox.shrink();
    return Column(
      children: [
        _folioBar(),
        const Divider(height: 1),
        if (includeSearch) ...[
          _searchField(),
          const Divider(height: 1),
        ],
        Expanded(
          child: controller.isSearching
              ? _searchResultsList(onNoteSelected: onNoteSelected)
              : FolderTreeView(
                  root: tree,
                  selectedNotePath: controller.selectedNotePath,
                  // Always-scrollable on phones so pull-to-refresh fires even
                  // when the tree is short.
                  physics:
                      scrollable ? const AlwaysScrollableScrollPhysics() : null,
                  canRevealInFileManager:
                      canRevealInFileManager && controller.isLocalFolio,
                  readOnly: controller.isBrowsing,
                  onNoteTap: (note) {
                    controller.selectNote(note);
                    onNoteSelected?.call();
                  },
                  onFolderAction: _handleFolderAction,
                  onNoteAction: _handleNoteAction,
                  onOpenFolderNote: controller.openFolderNote,
                ),
        ),
      ],
    );
  }

  /// Search box that filters notes by title/tags via the sidecar index.
  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: TextField(
        key: const Key('noteSearchField'),
        controller: _searchController,
        onChanged: controller.setSearchQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: _l10n.searchNotes,
          border: const OutlineInputBorder(),
          suffixIcon: controller.isSearching
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: _l10n.cancel,
                  onPressed: () {
                    _searchController.clear();
                    controller.clearSearch();
                  },
                )
              : null,
        ),
      ),
    );
  }

  /// Flat list of search hits; tapping one opens it (and, on phones, swipes to
  /// the editor via [onNoteSelected]).
  Widget _searchResultsList({VoidCallback? onNoteSelected}) {
    final results = controller.searchResults;
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_l10n.searchNoResults, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final note = results[i];
        final slash = note.path.lastIndexOf('/');
        final folder = slash < 0 ? '' : note.path.substring(0, slash);
        return ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(note.title),
          subtitle: folder.isEmpty ? null : Text(folder),
          selected: note.path == controller.selectedNotePath,
          onTap: () {
            controller.selectNote(note);
            onNoteSelected?.call();
          },
        );
      },
    );
  }

  /// Absolute folder of the open note, used to resolve relative image links in
  /// the preview (null for non-local repositories or when no note is open).
  String? _imageBaseDir() {
    final notePath = controller.selectedNotePath;
    if (notePath == null) return null;
    final slash = notePath.lastIndexOf('/');
    final folder = slash < 0 ? '' : notePath.substring(0, slash);
    return controller.localAbsolutePath(folder);
  }

  /// The phone "+" action: create a note, picking the destination folder
  /// (notes can't live at the root). Defaults to the open note's folder.
  Future<void> _promptNewNote() async {
    final tree = controller.tree;
    if (tree == null) return;

    final folders = <({String path, String label})>[];
    void walk(FolderNode folder, int depth) {
      for (final child in folder.folders) {
        folders.add((path: child.path, label: '${'   ' * depth}${child.name}'));
        walk(child, depth + 1);
      }
    }

    walk(tree, 0);
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.createFolderFirst)),
      );
      _goToPage(0);
      return;
    }

    // Default to the open note's folder when there is one.
    var folderPath = folders.first.path;
    final notePath = controller.selectedNotePath;
    if (notePath != null) {
      final slash = notePath.lastIndexOf('/');
      final current = slash < 0 ? '' : notePath.substring(0, slash);
      if (folders.any((f) => f.path == current)) folderPath = current;
    }

    final result = await _showNewNoteDialog(folders, folderPath);
    if (result != null && result.name.isNotEmpty) {
      await controller.createNote(result.name, folderPath: result.folder);
      _goToPage(1);
    }
  }

  Future<({String name, String folder})?> _showNewNoteDialog(
    List<({String path, String label})> folders,
    String initialFolder,
  ) {
    final field = TextEditingController();
    var folder = initialFolder;
    return showDialog<({String name, String folder})>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(l10n.newNote),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: field,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l10n.noteName),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(l10n.folderColon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: folder,
                        onChanged: (v) => setLocal(() => folder = v ?? folder),
                        items: [
                          for (final f in folders)
                            DropdownMenuItem(
                              value: f.path,
                              child: Text(f.label),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context)
                    .pop((name: field.text.trim(), folder: folder)),
                child: Text(l10n.create),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _attachFile() async {
    // Accept any file: images are embedded, other types become openable links.
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await controller.attachToCurrentNote(file.name, bytes);
  }

  /// A thin line separating the toolbar from the content. When the selected
  /// note's folder has a color, the line takes that color as a visual cue.
  Widget _accentDivider() {
    final color = colorFromHex(controller.selectedNoteFolderColor) ??
        Theme.of(context).colorScheme.outlineVariant;
    return Container(height: 2, color: color);
  }

  /// The folio switcher at the top of the tree: the current Folio's name, tap to
  /// drop down recent Folios and jump between them (or close this one). This is
  /// the "switch workspace" control — moved out of the title bar and aligned
  /// with the editor breadcrumb across the sub-header row.
  Widget _folioSwitcher() {
    final scheme = Theme.of(context).colorScheme;
    final recents = controller.recentFolios;
    return PopupMenuButton<int>(
      tooltip: _l10n.switchFolio,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: (i) {
        if (i == -1) {
          controller.closeFolio();
        } else {
          controller.openRecentFolio(recents[i]);
        }
      },
      itemBuilder: (_) => [
        for (var i = 0; i < recents.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(_recentTypeIcon(recents[i].type), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(recents[i].name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        if (recents.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<int>(value: -1, child: Text(_l10n.closeFolio)),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.folioName,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  static IconData _recentTypeIcon(String type) => switch (type) {
        'webdav' => Icons.cloud_outlined,
        'onedrive' => Icons.cloud_queue_outlined,
        'git' => Icons.cloud_download_outlined,
        'saf' => Icons.phone_android,
        _ => Icons.folder_outlined,
      };

  /// The folio row atop the tree: the folio switcher plus the folder-level
  /// actions (reveal in file manager, new top-level folder), so the folio has
  /// its own action row that mirrors the per-folder rows below it.
  Widget _folioBar() {
    final canReveal = canRevealInFileManager && controller.isLocalFolio;
    return Row(
      children: [
        Expanded(child: _folioSwitcher()),
        if (canReveal)
          IconButton(
            tooltip: _l10n.openFolioInFileManager,
            icon: const Icon(Icons.folder_open_outlined),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              final abs = controller.localAbsolutePath('');
              if (abs != null) revealInFileManager(abs);
            },
          ),
        if (!controller.isBrowsing)
          IconButton(
            tooltip: _l10n.newTopLevelFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            visualDensity: VisualDensity.compact,
            onPressed: _promptNewRootFolder,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _errorBanner(String message) {
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      content: Text(message),
      leading: const Icon(Icons.error_outline),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text(_l10n.copyError),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: message));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_l10n.copiedToClipboard),
                duration: const Duration(seconds: 1),
              ));
            }
          },
        ),
      ],
    );
  }

  /// Shown when a sync was withheld because a side looks empty (likely a flaky
  /// connection). The user explicitly confirms before any deletion propagates.
  Widget _emptySyncBanner() {
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      content: Text(_l10n.emptySyncWarning),
      leading: const Icon(Icons.warning_amber_outlined),
      actions: [
        TextButton(
          onPressed: () => controller.dismissEmptyingSync(),
          child: Text(_l10n.cancel),
        ),
        TextButton(
          onPressed: () => controller.confirmEmptyingSync(),
          child: Text(_l10n.syncAnyway),
        ),
      ],
    );
  }

  Future<void> _promptNewRootFolder() async {
    final l10n = _l10n;
    final name = await _promptName(
      title: l10n.newTopLevelFolder,
      label: l10n.folderName,
    );
    if (name != null && name.isNotEmpty) {
      await controller.createFolder(name);
    }
  }

  Future<void> _handleFolderAction(FolderNode folder, TreeAction action) async {
    final l10n = _l10n;
    switch (action) {
      case TreeAction.newNote:
        final name = await _promptName(title: l10n.newNote, label: l10n.noteName);
        if (name != null && name.isNotEmpty) {
          await controller.createNote(name, folderPath: folder.path);
          _goToPage(1); // on phones, swipe to the editor (no-op on desktop)
        }
      case TreeAction.newSubfolder:
        final name =
            await _promptName(title: l10n.newSubfolder, label: l10n.folderName);
        if (name != null && name.isNotEmpty) {
          await controller.createFolder(name, parentPath: folder.path);
        }
      case TreeAction.renameFolder:
        final name = await _promptName(
          title: l10n.renameFolder,
          label: l10n.folderName,
          initialValue: folder.name,
          confirmLabel: l10n.rename,
        );
        if (name != null && name.isNotEmpty && name != folder.name) {
          await controller.renameFolder(folder.path, name);
        }
      case TreeAction.setColor:
        final choice = await _promptFolderColor(folder.color);
        if (choice != null) {
          await controller.setFolderColor(
            folder.path,
            choice.isEmpty ? null : choice,
          );
        }
      case TreeAction.openInFileManager:
        final abs = controller.localAbsolutePath(folder.path);
        if (abs != null) await revealInFileManager(abs);
      case TreeAction.deleteFolder:
        final confirmed = await _confirmDelete(
          l10n.deleteFolderTitle(folder.name),
          l10n.deleteFolderBody,
        );
        if (confirmed) await controller.deleteFolder(folder.path);
      case TreeAction.openContainingFolder:
      case TreeAction.deleteNote:
      case TreeAction.collapseAll:
      case TreeAction.expandAll:
        break; // not applicable here (collapse/expand handled inside the tree)
    }
  }

  /// Shows the notes that link to the open note (incoming references); tapping
  /// one navigates to it.
  Future<void> _showBacklinks(BuildContext context) async {
    final notePath = controller.selectedNotePath;
    if (notePath == null) return;
    final links = await controller.backlinksFor(notePath);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l10n.backlinks),
          content: SizedBox(
            width: 360,
            child: links.isEmpty
                ? Text(l10n.noBacklinks)
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final n in links)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.description_outlined),
                            title: Text(n.title),
                            subtitle: n.path.contains('/')
                                ? Text(n.path.substring(0, n.path.lastIndexOf('/')))
                                : null,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              controller.selectNote(n);
                            },
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleNoteAction(NoteNode note, TreeAction action) async {
    switch (action) {
      case TreeAction.openContainingFolder:
        final abs = controller.localAbsolutePath(note.path);
        if (abs != null) await revealInFileManager(abs, selectFile: true);
      case TreeAction.deleteNote:
        final l10n = _l10n;
        final confirmed = await _confirmDelete(
          l10n.deleteNoteTitle(note.title),
          l10n.deleteNoteBody,
        );
        if (confirmed) await controller.deleteNote(note.path);
      default:
        break; // other actions are folder-only
    }
  }

  /// Returns null if cancelled, '' to clear the color, or a `#RRGGBB` hex.
  Future<String?> _promptFolderColor(String? current) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.folderColor),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final swatch in folderColorPalette)
                _ColorSwatch(
                  color: colorFromHex(swatch.hex)!,
                  tooltip: swatch.label,
                  selected: current == swatch.hex,
                  onTap: () => Navigator.of(context).pop(swatch.hex),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: Text(l10n.noColor),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDelete(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String initialValue = '',
    String? confirmLabel,
  }) async {
    final field = TextEditingController(text: initialValue);
    field.selection =
        TextSelection(baseOffset: 0, extentOffset: initialValue.length);
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: field,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(field.text.trim()),
              child: Text(confirmLabel ?? l10n.create),
            ),
          ],
        );
      },
    );
  }
}

/// A tappable color circle used in the folder-color picker.
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.black26,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Windows/Linux window buttons for the custom title bar (macOS uses native
/// traffic-lights). Close routes through the tray guard (hide to tray).
class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinBtn(icon: Icons.remove, onTap: minimizeWindow),
        _WinBtn(icon: Icons.crop_square, onTap: toggleMaximizeWindow),
        _WinBtn(icon: Icons.close, onTap: closeWindow, danger: true),
      ],
    );
  }
}

class _WinBtn extends StatelessWidget {
  const _WinBtn({required this.icon, required this.onTap, this.danger = false});

  final IconData icon;
  final Future<void> Function() onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 46,
      height: 44,
      child: InkWell(
        onTap: () => onTap(),
        hoverColor:
            danger ? const Color(0xFFD64545) : scheme.onSurface.withValues(alpha: .08),
        child: Icon(icon, size: 15, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// The bracket-dot app mark, painted on a cream tile so it keeps its identity in
/// both themes (the way a real app icon does).
class _MarginMarkPainter extends CustomPainter {
  const _MarginMarkPainter(this.dotColor);

  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.28)),
      Paint()..color = const Color(0xFFEFE7D6),
    );
    final s = size.width / 32;
    final ink = Paint()
      ..color = const Color(0xFF211E18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(19 * s, 9 * s)
        ..lineTo(12 * s, 9 * s)
        ..lineTo(12 * s, 23 * s)
        ..lineTo(19 * s, 23 * s),
      ink,
    );
    canvas.drawCircle(Offset(22.5 * s, 16 * s), 2.4 * s, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_MarginMarkPainter old) => old.dotColor != dotColor;
}
