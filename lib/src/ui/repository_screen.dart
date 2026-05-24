// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../content/repository_node.dart';
import '../desktop/file_reveal.dart';
import '../desktop/startup_service.dart';
import 'app_controller.dart';
import 'color_hex.dart';
import 'settings_dialog.dart';
import 'widgets/folder_tree.dart';
import 'widgets/markdown_preview.dart';
import 'widgets/note_editor_pane.dart';

/// The two-panel desktop layout (DESIGN.md): a collapsible folder tree on the
/// left, the note editor on the right.
class RepositoryScreen extends StatefulWidget {
  final AppController controller;
  final StartupService startupService;

  const RepositoryScreen({
    super.key,
    required this.controller,
    this.startupService = const NoopStartupService(),
  });

  @override
  State<RepositoryScreen> createState() => _RepositoryScreenState();
}

class _RepositoryScreenState extends State<RepositoryScreen> {
  /// Breakpoint below which the phone (drawer) layout is used.
  static const double _wideBreakpoint = 720;

  bool _showTree = true;

  // Phone layout: three swipeable pages (0 folders, 1 editor, 2 preview).
  final PageController _pageController = PageController(initialPage: 1);
  int _currentPage = 1;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _pageController.dispose();
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
          tooltip: _showTree ? 'Hide folders' : 'Show folders',
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
              tooltip: 'Attach file',
              icon: const Icon(Icons.attach_file),
              onPressed: _attachFile,
            ),
          _saveAction(),
          _settingsAction(),
          _closeAction(),
        ],
        bottom: _busyBar(),
      ),
      body: Column(
        children: [
          _accentDivider(),
          if (controller.error != null) _errorBanner(controller.error!),
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
      child: Text(
        _mobileTitle(),
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
            : Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: _treePanelContent(onNoteSelected: () => _goToPage(1)),
              ),
        NoteEditorPane(
          notePath: notePath,
          body: controller.workingBody,
          onChanged: controller.updateBody,
          mode: EditorViewMode.edit, // preview is its own page here
          revision: controller.editorRevision,
          imageBaseDir: _imageBaseDir(),
        ),
        notePath == null
            ? const Center(child: Text('Select a note to preview.'))
            : MarkdownPreview(
                data: controller.workingBody,
                imageBaseDir: _imageBaseDir(),
              ),
      ],
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
            _pageNavButton(0, Icons.folder_outlined, 'Folders'),
            _pageNavButton(1, Icons.edit_note, 'Editor'),
            _pageNavButton(2, Icons.visibility_outlined, 'Preview'),
            const Spacer(),
            IconButton.filled(
              tooltip: 'New note',
              icon: const Icon(Icons.add),
              onPressed: _promptNewNote,
            ),
            const Spacer(),
            if (hasNote)
              IconButton(
                tooltip: 'Attach file',
                icon: const Icon(Icons.attach_file),
                onPressed: _attachFile,
              ),
            if (hasNote) _saveAction(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'settings') _openSettings();
                if (value == 'close') controller.closeRepository();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'settings', child: Text('Settings')),
                PopupMenuItem(value: 'close', child: Text('Close repository')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageNavButton(int index, IconData icon, String tooltip) {
    final selected = _currentPage == index;
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      color: selected ? Theme.of(context).colorScheme.primary : null,
      icon: Icon(icon),
      onPressed: () => _goToPage(index),
    );
  }

  // --- shared app-bar actions ---

  Widget _saveAction() => IconButton(
        tooltip: 'Save',
        icon: const Icon(Icons.save_outlined),
        onPressed: controller.isDirty ? () => controller.save() : null,
      );

  Widget _settingsAction() => IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => SettingsDialog.show(
          context,
          startupService: widget.startupService,
          controller: controller,
        ),
      );

  Widget _closeAction() => IconButton(
        tooltip: 'Close repository',
        icon: const Icon(Icons.close),
        onPressed: controller.closeRepository,
      );

  PreferredSizeWidget? _busyBar() => controller.isBusy
      ? const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: LinearProgressIndicator(minHeight: 2),
        )
      : null;

  /// Wide title: repository name, plus the note path when the tree is hidden.
  String _wideTitle() {
    final repo = controller.repositoryName;
    final notePath = controller.selectedNotePath;
    if (!_showTree && notePath != null) {
      return '$repo / ${notePath.replaceAll('/', ' / ')}';
    }
    return repo;
  }

  /// Narrow title: the open note's name, or the repository name.
  String _mobileTitle() {
    final notePath = controller.selectedNotePath;
    if (notePath == null) return controller.repositoryName;
    final name = notePath.split('/').last;
    return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }

  Widget _viewModeControl() {
    return SegmentedButton<EditorViewMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: EditorViewMode.edit,
          icon: Icon(Icons.edit_note),
          tooltip: 'Editor',
        ),
        ButtonSegment(
          value: EditorViewMode.split,
          icon: Icon(Icons.vertical_split_outlined),
          tooltip: 'Split (editor + preview)',
        ),
        ButtonSegment(
          value: EditorViewMode.preview,
          icon: Icon(Icons.visibility_outlined),
          tooltip: 'Preview',
        ),
      ],
      selected: {controller.viewMode},
      onSelectionChanged: (selection) =>
          controller.setViewMode(selection.first),
    );
  }

  Widget _wideContent() {
    final tree = controller.tree;
    final editor = NoteEditorPane(
      notePath: controller.selectedNotePath,
      body: controller.workingBody,
      onChanged: controller.updateBody,
      mode: controller.viewMode,
      revision: controller.editorRevision,
      imageBaseDir: _imageBaseDir(),
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
  Widget _treePanelContent({VoidCallback? onNoteSelected}) {
    final tree = controller.tree;
    if (tree == null) return const SizedBox.shrink();
    return Column(
      children: [
        _treeHeader(),
        const Divider(height: 1),
        Expanded(
          child: FolderTreeView(
            root: tree,
            selectedNotePath: controller.selectedNotePath,
            canRevealInFileManager:
                canRevealInFileManager && controller.isLocalRepository,
            onNoteTap: (note) {
              controller.selectNote(note);
              onNoteSelected?.call();
            },
            onFolderAction: _handleFolderAction,
            onNoteAction: _handleNoteAction,
          ),
        ),
      ],
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
        const SnackBar(content: Text('Create a folder first (Folders page).')),
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
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New note'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: field,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Note name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Folder:'),
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
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context)
                    .pop((name: field.text.trim(), folder: folder)),
                child: const Text('Create'),
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
    final canReveal = canRevealInFileManager && controller.isLocalRepository;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Text(
            'Folders',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const Spacer(),
          if (canReveal)
            IconButton(
              tooltip: 'Open repository in file manager',
              icon: const Icon(Icons.folder_open_outlined),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final abs = controller.localAbsolutePath('');
                if (abs != null) revealInFileManager(abs);
              },
            ),
          IconButton(
            tooltip: 'New top-level folder',
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
      actions: const [SizedBox.shrink()],
    );
  }

  Future<void> _promptNewRootFolder() async {
    final name = await _promptName(
      title: 'New top-level folder',
      label: 'Folder name',
    );
    if (name != null && name.isNotEmpty) {
      await controller.createFolder(name);
    }
  }

  Future<void> _handleFolderAction(FolderNode folder, TreeAction action) async {
    switch (action) {
      case TreeAction.newNote:
        final name = await _promptName(title: 'New note', label: 'Note name');
        if (name != null && name.isNotEmpty) {
          await controller.createNote(name, folderPath: folder.path);
          _goToPage(1); // on phones, swipe to the editor (no-op on desktop)
        }
      case TreeAction.newSubfolder:
        final name =
            await _promptName(title: 'New subfolder', label: 'Folder name');
        if (name != null && name.isNotEmpty) {
          await controller.createFolder(name, parentPath: folder.path);
        }
      case TreeAction.renameFolder:
        final name = await _promptName(
          title: 'Rename folder',
          label: 'Folder name',
          initialValue: folder.name,
          confirmLabel: 'Rename',
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
          'Delete folder "${folder.name}"?',
          'This deletes the folder and all notes inside it.',
        );
        if (confirmed) await controller.deleteFolder(folder.path);
      case TreeAction.deleteNote:
        break; // not applicable to folders
    }
  }

  Future<void> _handleNoteAction(NoteNode note, TreeAction action) async {
    if (action == TreeAction.deleteNote) {
      final confirmed = await _confirmDelete(
        'Delete note "${note.title}"?',
        'This permanently removes the note file.',
      );
      if (confirmed) await controller.deleteNote(note.path);
    }
  }

  /// Returns null if cancelled, '' to clear the color, or a `#RRGGBB` hex.
  Future<String?> _promptFolderColor(String? current) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Folder color'),
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
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('No color'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDelete(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String initialValue = '',
    String confirmLabel = 'Create',
  }) async {
    final field = TextEditingController(text: initialValue);
    field.selection =
        TextSelection(baseOffset: 0, extentOffset: initialValue.length);
    return showDialog<String>(
      context: context,
      builder: (context) {
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(field.text.trim()),
              child: Text(confirmLabel),
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
