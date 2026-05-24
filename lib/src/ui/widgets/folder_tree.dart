// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../content/repository_node.dart';
import '../color_hex.dart';

/// Contextual actions available from the tree's per-item menus.
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
/// Each folder and note has a ⋮ menu (tap) for its actions — New note, rename,
/// delete, etc. — so everything is reachable by touch as well as by right-click
/// on desktop. Adding a top-level folder is a toolbar action on the screen.
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
          // Right-click on desktop opens the same menu.
          onSecondaryTapDown: (details) =>
              _showMenuAt(context, details.globalPosition, _folderMenuItems(),
                  (a) => onFolderAction(folder, a)),
          child: Text(folder.name),
        ),
      ),
      trailing: PopupMenuButton<TreeAction>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Folder actions',
        itemBuilder: (_) => _folderMenuItems(),
        onSelected: (a) => onFolderAction(folder, a),
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: _childrenOf(folder),
    );
  }

  Widget _noteTile(NoteNode note) {
    return Builder(
      builder: (context) => GestureDetector(
        onSecondaryTapDown: (details) =>
            _showMenuAt(context, details.globalPosition, _noteMenuItems(),
                (a) => onNoteAction(note, a)),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(note.title),
          selected: note.path == selectedNotePath,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
          trailing: PopupMenuButton<TreeAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Note actions',
            itemBuilder: (_) => _noteMenuItems(),
            onSelected: (a) => onNoteAction(note, a),
          ),
          onTap: () => onNoteTap(note),
        ),
      ),
    );
  }

  List<PopupMenuEntry<TreeAction>> _folderMenuItems() => [
        const PopupMenuItem(value: TreeAction.newNote, child: Text('New note')),
        const PopupMenuItem(
            value: TreeAction.newSubfolder, child: Text('New subfolder')),
        const PopupMenuItem(
            value: TreeAction.renameFolder, child: Text('Rename…')),
        const PopupMenuItem(value: TreeAction.setColor, child: Text('Set color…')),
        if (canRevealInFileManager)
          const PopupMenuItem(
            value: TreeAction.openInFileManager,
            child: Text('Open in file manager'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: TreeAction.deleteFolder, child: Text('Delete folder')),
      ];

  List<PopupMenuEntry<TreeAction>> _noteMenuItems() => const [
        PopupMenuItem(value: TreeAction.deleteNote, child: Text('Delete note')),
      ];

  Future<void> _showMenuAt(
    BuildContext context,
    Offset position,
    List<PopupMenuEntry<TreeAction>> items,
    void Function(TreeAction) onSelected,
  ) async {
    final action = await showMenu<TreeAction>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: items,
    );
    if (action != null) onSelected(action);
  }
}
