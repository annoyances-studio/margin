// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../content/tree_node.dart';
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
    final l10n = AppLocalizations.of(context);
    final children = _childrenOf(root, l10n);
    if (children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.emptyFolders,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(children: children);
  }

  List<Widget> _childrenOf(FolderNode folder, AppLocalizations l10n) => [
        for (final child in folder.folders) _folderTile(child, l10n),
        for (final note in folder.notes) _noteTile(note, l10n),
      ];

  Widget _folderTile(FolderNode folder, AppLocalizations l10n) {
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
          onSecondaryTapDown: (details) => _showMenuAt(
              context,
              details.globalPosition,
              _folderMenuItems(l10n),
              (a) => onFolderAction(folder, a)),
          child: Text(folder.name),
        ),
      ),
      trailing: PopupMenuButton<TreeAction>(
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.folderActions,
        itemBuilder: (_) => _folderMenuItems(l10n),
        onSelected: (a) => onFolderAction(folder, a),
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: _childrenOf(folder, l10n),
    );
  }

  Widget _noteTile(NoteNode note, AppLocalizations l10n) {
    return Builder(
      builder: (context) => GestureDetector(
        onSecondaryTapDown: (details) => _showMenuAt(
            context,
            details.globalPosition,
            _noteMenuItems(l10n),
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
            tooltip: l10n.noteActions,
            itemBuilder: (_) => _noteMenuItems(l10n),
            onSelected: (a) => onNoteAction(note, a),
          ),
          onTap: () => onNoteTap(note),
        ),
      ),
    );
  }

  List<PopupMenuEntry<TreeAction>> _folderMenuItems(AppLocalizations l10n) => [
        PopupMenuItem(value: TreeAction.newNote, child: Text(l10n.newNote)),
        PopupMenuItem(
            value: TreeAction.newSubfolder, child: Text(l10n.newSubfolder)),
        PopupMenuItem(
            value: TreeAction.renameFolder, child: Text(l10n.renameEllipsis)),
        PopupMenuItem(
            value: TreeAction.setColor, child: Text(l10n.setColorEllipsis)),
        if (canRevealInFileManager)
          PopupMenuItem(
            value: TreeAction.openInFileManager,
            child: Text(l10n.openInFileManager),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: TreeAction.deleteFolder, child: Text(l10n.deleteFolder)),
      ];

  List<PopupMenuEntry<TreeAction>> _noteMenuItems(AppLocalizations l10n) => [
        PopupMenuItem(value: TreeAction.deleteNote, child: Text(l10n.deleteNote)),
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
