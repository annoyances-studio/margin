// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../content/repository_node.dart';
import '../color_hex.dart';

/// Contextual actions available from the tree's right-click menus.
enum TreeAction {
  newNote,
  newSubfolder,
  renameFolder,
  setColor,
  openInFileManager,
  deleteFolder,
  deleteNote,
}

/// Renders the repository tree: folders as expandable tiles, notes as leaves.
///
/// Creation and deletion are contextual: right-click a folder to add a note or
/// subfolder inside it (or delete it), right-click a note to delete it. Adding
/// a top-level folder is a toolbar action on the screen.
class FolderTreeView extends StatelessWidget {
  final FolderNode root;
  final String? selectedNotePath;

  /// Whether to offer "Open in file manager" (local desktop repositories only).
  final bool canRevealInFileManager;
  final ValueChanged<NoteNode> onNoteTap;
  final void Function(FolderNode folder, TreeAction action) onFolderAction;
  final void Function(NoteNode note, TreeAction action) onNoteAction;

  const FolderTreeView({
    super.key,
    required this.root,
    required this.onNoteTap,
    required this.onFolderAction,
    required this.onNoteAction,
    this.selectedNotePath,
    this.canRevealInFileManager = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = _childrenOf(root);
    if (children.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No folders yet.\nUse "New folder" to start.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(children: children);
  }

  List<Widget> _childrenOf(FolderNode folder) => [
        for (final child in folder.folders) _folderTile(child),
        for (final note in folder.notes) _noteTile(note),
      ];

  Widget _folderTile(FolderNode folder) {
    final color = colorFromHex(folder.color);
    return ExpansionTile(
      key: PageStorageKey(folder.path),
      initiallyExpanded: true,
      leading: Icon(
        color != null ? Icons.folder : Icons.folder_outlined,
        color: color,
      ),
      title: Builder(
        builder: (context) => GestureDetector(
          onSecondaryTapDown: (details) =>
              _showFolderMenu(context, folder, details.globalPosition),
          child: Text(folder.name),
        ),
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: _childrenOf(folder),
    );
  }

  Widget _noteTile(NoteNode note) {
    return Builder(
      builder: (context) => GestureDetector(
        onSecondaryTapDown: (details) =>
            _showNoteMenu(context, note, details.globalPosition),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(note.title),
          selected: note.path == selectedNotePath,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
          onTap: () => onNoteTap(note),
        ),
      ),
    );
  }

  Future<void> _showFolderMenu(
      BuildContext context, FolderNode folder, Offset position) async {
    final action = await showMenu<TreeAction>(
      context: context,
      position: _menuPosition(position),
      items: [
        const PopupMenuItem(value: TreeAction.newNote, child: Text('New note')),
        const PopupMenuItem(
            value: TreeAction.newSubfolder, child: Text('New subfolder')),
        const PopupMenuItem(
            value: TreeAction.renameFolder, child: Text('Rename…')),
        const PopupMenuItem(
            value: TreeAction.setColor, child: Text('Set color…')),
        if (canRevealInFileManager)
          const PopupMenuItem(
            value: TreeAction.openInFileManager,
            child: Text('Open in file manager'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: TreeAction.deleteFolder, child: Text('Delete folder')),
      ],
    );
    if (action != null) onFolderAction(folder, action);
  }

  Future<void> _showNoteMenu(
      BuildContext context, NoteNode note, Offset position) async {
    final action = await showMenu<TreeAction>(
      context: context,
      position: _menuPosition(position),
      items: const [
        PopupMenuItem(value: TreeAction.deleteNote, child: Text('Delete note')),
      ],
    );
    if (action != null) onNoteAction(note, action);
  }

  RelativeRect _menuPosition(Offset global) =>
      RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy);
}
