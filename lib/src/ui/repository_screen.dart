// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../content/repository_node.dart';
import 'app_controller.dart';
import 'color_hex.dart';
import 'widgets/folder_tree.dart';
import 'widgets/note_editor_pane.dart';

/// The two-panel desktop layout (DESIGN.md): a collapsible folder tree on the
/// left, the note editor on the right.
class RepositoryScreen extends StatefulWidget {
  final AppController controller;

  const RepositoryScreen({super.key, required this.controller});

  @override
  State<RepositoryScreen> createState() => _RepositoryScreenState();
}

class _RepositoryScreenState extends State<RepositoryScreen> {
  bool _showTree = true;
  EditorViewMode _viewMode = EditorViewMode.split;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: _showTree ? 'Hide folders' : 'Show folders',
              icon: Icon(_showTree ? Icons.menu_open : Icons.menu),
              onPressed: () => setState(() => _showTree = !_showTree),
            ),
            title: Text(_titleText()),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _viewModeControl(),
              ),
              IconButton(
                tooltip: 'New top-level folder',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _promptNewRootFolder,
              ),
              IconButton(
                tooltip: 'Save',
                icon: const Icon(Icons.save_outlined),
                onPressed: controller.isDirty ? () => controller.save() : null,
              ),
              IconButton(
                tooltip: 'Close repository',
                icon: const Icon(Icons.close),
                onPressed: controller.closeRepository,
              ),
            ],
            bottom: controller.isBusy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(2),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : null,
          ),
          body: Column(
            children: [
              if (controller.error != null) _errorBanner(controller.error!),
              Expanded(child: _body()),
            ],
          ),
        );
      },
    );
  }

  /// Always shows the repository name; when the tree is hidden it also appends
  /// the open note's full path so you still know where you are.
  String _titleText() {
    final repo = controller.repositoryName;
    final notePath = controller.selectedNotePath;
    if (!_showTree && notePath != null) {
      return '$repo / ${notePath.replaceAll('/', ' / ')}';
    }
    return repo;
  }

  Widget _viewModeControl() {
    return SegmentedButton<EditorViewMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: EditorViewMode.edit,
          icon: Icon(Icons.code),
          tooltip: 'Code',
        ),
        ButtonSegment(
          value: EditorViewMode.split,
          icon: Icon(Icons.vertical_split_outlined),
          tooltip: 'Split',
        ),
        ButtonSegment(
          value: EditorViewMode.preview,
          icon: Icon(Icons.visibility_outlined),
          tooltip: 'Preview',
        ),
      ],
      selected: {_viewMode},
      onSelectionChanged: (selection) =>
          setState(() => _viewMode = selection.first),
    );
  }

  Widget _body() {
    final tree = controller.tree;
    final editor = NoteEditorPane(
      notePath: controller.selectedNotePath,
      body: controller.workingBody,
      onChanged: controller.updateBody,
      mode: _viewMode,
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
            child: FolderTreeView(
              root: tree,
              selectedNotePath: controller.selectedNotePath,
              onNoteTap: controller.selectNote,
              onFolderAction: _handleFolderAction,
              onNoteAction: _handleNoteAction,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: editor),
      ],
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
        }
      case TreeAction.newSubfolder:
        final name =
            await _promptName(title: 'New subfolder', label: 'Folder name');
        if (name != null && name.isNotEmpty) {
          await controller.createFolder(name, parentPath: folder.path);
        }
      case TreeAction.setColor:
        final choice = await _promptFolderColor(folder.color);
        if (choice != null) {
          await controller.setFolderColor(
            folder.path,
            choice.isEmpty ? null : choice,
          );
        }
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
  }) async {
    final field = TextEditingController();
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
              child: const Text('Create'),
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
