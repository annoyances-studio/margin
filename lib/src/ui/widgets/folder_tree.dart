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
  openContainingFolder,
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

  /// Opens (or creates) a folder's folder-level note — fired by tapping the
  /// folder name.
  final void Function(FolderNode folder) onOpenFolderNote;

  /// Scroll physics for the list. The mobile pages pass
  /// [AlwaysScrollableScrollPhysics] so a pull-to-refresh gesture works even
  /// when the tree is short enough to fit without scrolling.
  final ScrollPhysics? physics;

  const FolderTreeView({
    super.key,
    required this.root,
    required this.onNoteTap,
    required this.onFolderAction,
    required this.onNoteAction,
    required this.onOpenFolderNote,
    this.selectedNotePath,
    this.canRevealInFileManager = false,
    this.physics,
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
    return ListView(physics: physics, children: children);
  }

  List<Widget> _childrenOf(FolderNode folder, AppLocalizations l10n) => [
        for (final child in folder.folders)
          _FolderTile(
            folder: child,
            menuItems: _folderMenuItems(l10n),
            menuTooltip: l10n.folderActions,
            onAction: (a) => onFolderAction(child, a),
            onOpenNote: () => onOpenFolderNote(child),
            folderNoteTooltip: l10n.openFolderNote,
            children: _childrenOf(child, l10n),
          ),
        for (final note in folder.notes) _noteTile(note, l10n),
      ];

  Widget _noteTile(NoteNode note, AppLocalizations l10n) {
    return Builder(
      builder: (context) => GestureDetector(
        onSecondaryTapDown: (details) => _showTreeMenu(
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
        if (canRevealInFileManager)
          PopupMenuItem(
            value: TreeAction.openContainingFolder,
            child: Text(l10n.openContainingFolder),
          ),
        PopupMenuItem(value: TreeAction.deleteNote, child: Text(l10n.deleteNote)),
      ];

}

/// A folder row with an explicit expand/collapse chevron beside its actions
/// menu. The chevron matters because overriding [ExpansionTile.trailing] with
/// the ⋮ menu removes the built-in rotating arrow — without it a collapsed
/// folder is indistinguishable from an empty one.
class _FolderTile extends StatefulWidget {
  final FolderNode folder;
  final List<Widget> children;
  final List<PopupMenuEntry<TreeAction>> menuItems;
  final String menuTooltip;
  final void Function(TreeAction) onAction;
  final VoidCallback onOpenNote;
  final String folderNoteTooltip;

  const _FolderTile({
    required this.folder,
    required this.children,
    required this.menuItems,
    required this.menuTooltip,
    required this.onAction,
    required this.onOpenNote,
    required this.folderNoteTooltip,
  });

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(widget.folder.color);
    return ExpansionTile(
      key: PageStorageKey(widget.folder.path),
      initiallyExpanded: true,
      onExpansionChanged: (v) => setState(() => _expanded = v),
      leading: Icon(
        color != null ? Icons.folder : Icons.folder_outlined,
        color: color,
      ),
      title: GestureDetector(
        // Tapping the name opens (or creates) the folder note; the chevron and
        // the rest of the row still expand/collapse.
        onTap: widget.onOpenNote,
        // Right-click on desktop opens the same menu.
        onSecondaryTapDown: (details) => _showTreeMenu(
          context,
          details.globalPosition,
          widget.menuItems,
          widget.onAction,
        ),
        child: Row(
          children: [
            Flexible(child: Text(widget.folder.name)),
            if (widget.folder.hasFolderNote) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: widget.folderNoteTooltip,
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRotation(
            // expand_more points down when open, rotates to point right (→)
            // when collapsed.
            turns: _expanded ? 0 : -0.25,
            duration: const Duration(milliseconds: 150),
            child: const Icon(Icons.expand_more, size: 20),
          ),
          PopupMenuButton<TreeAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: widget.menuTooltip,
            itemBuilder: (_) => widget.menuItems,
            onSelected: widget.onAction,
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: widget.children,
    );
  }
}

Future<void> _showTreeMenu(
  BuildContext context,
  Offset position,
  List<PopupMenuEntry<TreeAction>> items,
  void Function(TreeAction) onSelected,
) async {
  final action = await showMenu<TreeAction>(
    context: context,
    position:
        RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    items: items,
  );
  if (action != null) onSelected(action);
}
