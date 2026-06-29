// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // Phone layout: three swipeable pages (0 folders, 1 editor, 2 preview).
  final PageController _pageController = PageController(initialPage: 1);
  int _currentPage = 1;

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
            return constraints.maxWidth >= _wideBreakpoint
                ? _buildWide(context)
                : _buildNarrow(context);
          },
        );
      },
    );
  }

  // --- wide (desktop) layout: tree panel + editor, with view-mode control ---

  Widget _buildWide(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: _showTree ? _l10n.hideFolders : _l10n.showFolders,
          icon: Icon(_showTree ? Icons.menu_open : Icons.menu),
          onPressed: () => setState(() => _showTree = !_showTree),
        ),
        title: Text(_wideTitle()),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _viewModeControl(),
          ),
          if (controller.selectedNotePath != null)
            IconButton(
              tooltip: _l10n.backlinks,
              icon: const Icon(Icons.hub_outlined),
              onPressed: () => _showBacklinks(context),
            ),
          if (controller.selectedNotePath != null && !controller.isBrowsing)
            IconButton(
              tooltip: _l10n.attachFile,
              icon: const Icon(Icons.attach_file),
              onPressed: _attachFile,
            ),
          if (!controller.isBrowsing) _saveAction(),
          if (controller.syncError != null) _syncRetryAction(),
          _overflowMenu(),
        ],
        bottom: _busyBar(),
      ),
      body: Column(
        children: [
          _accentDivider(),
          if (controller.error != null) _errorBanner(controller.error!),
          if (controller.syncNeedsEmptyConfirm) _emptySyncBanner(),
          Expanded(child: _wideContent()),
        ],
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
            : _pullToSync(
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: _treePanelContent(
                    onNoteSelected: () => _goToPage(1),
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
          onSpecialCopy: controller.canCopyNote ? _showCopyMenu : null,
          onSaveAttachment: controller.saveAttachmentForCurrentNote,
          onDownloadImage: controller.downloadImageAsAttachment,
          wordWrap: controller.wordWrap,
          readOnly: controller.isBrowsing,
          onOpenLink: controller.openLink,
        ),
        notePath == null
            ? Center(child: Text(_l10n.selectNoteToPreview))
            : _pullToSync(
                MarkdownPreview(
                  data: controller.workingBody,
                  imageBaseDir: _imageBaseDir(),
                  physics: const AlwaysScrollableScrollPhysics(),
                  onSpecialCopy: controller.canCopyNote ? _showCopyMenu : null,
                  onOpenLink: controller.openLink,
                ),
              ),
      ],
    );
  }

  /// Wraps a scrollable mobile page so a pull-down gesture triggers a sync —
  /// the touch equivalent of "Sync now". Only added when the Folio has a remote
  /// peer; otherwise the child is returned unchanged.
  Widget _pullToSync(Widget child) {
    if (!controller.canSync) return child;
    return RefreshIndicator(
      onRefresh: () => controller.syncNow(),
      child: child,
    );
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

  PreferredSizeWidget? _busyBar() => controller.isBusy
      ? const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: LinearProgressIndicator(minHeight: 2),
        )
      : null;

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
        onSpecialCopy: controller.canCopyNote ? _showCopyMenu : null,
        onSaveAttachment: controller.saveAttachmentForCurrentNote,
        onDownloadImage: controller.downloadImageAsAttachment,
        wordWrap: controller.wordWrap,
        readOnly: controller.isBrowsing,
        onOpenLink: controller.openLink,
      ),
    );

    if (!_showTree || tree == null) {
      return editor;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: Material(
            // A slightly distinct surface tone sets the sidebar apart from the
            // editor (VS Code / Claude-desktop style).
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: _treePanelContent(),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: editor),
      ],
    );
  }

  /// The folder tree with its header, shared by the desktop side panel and the
  /// phone folders page. [onNoteSelected] fires after a note is tapped (used on
  /// phones to swipe to the editor page).
  Widget _treePanelContent({
    VoidCallback? onNoteSelected,
    bool scrollable = false,
  }) {
    final tree = controller.tree;
    if (tree == null) return const SizedBox.shrink();
    return Column(
      children: [
        _treeHeader(),
        _searchField(),
        const Divider(height: 1),
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

  Widget _treeHeader() {
    final canReveal = canRevealInFileManager && controller.isLocalFolio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Text(
            _l10n.folders,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const Spacer(),
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
        ],
      ),
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
        break; // not applicable to folders
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
