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
  collapseAll,
  expandAll,
  deleteFolder,
  deleteNote,
}

/// Renders the repository tree: folders as expandable tiles, notes as leaves.
///
/// Each folder and note has a ⋮ menu (tap) for its actions — New note, rename,
/// delete, collapse/expand, etc. — so everything is reachable by touch as well
/// as by right-click on desktop. Adding a top-level folder is a toolbar action
/// on the screen.
///
/// Expansion state is held centrally (a set of collapsed folder paths) rather
/// than per-tile, so "collapse/expand all" can act on a whole subtree at once.
class FolderTreeView extends StatefulWidget {
  final FolderNode root;
  final String? selectedNotePath;

  /// Whether to offer "Open in file manager" (local desktop repositories only).
  final bool canRevealInFileManager;

  /// Read-only mode (browsed plain folder): the per-item menus offer only
  /// non-mutating actions (reveal in file manager), never new/rename/delete.
  final bool readOnly;
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
    this.readOnly = false,
    this.physics,
  });

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  /// Collapsed folder paths. Folders default **collapsed** (see
  /// [_applyDefaultCollapse]) so you see the structure first and drill in.
  final Set<String> _collapsed = {};

  /// Folder paths we've already applied the collapsed-by-default rule to, so a
  /// folder the user later expanded stays expanded across rebuilds (and only
  /// newly-appearing folders start collapsed).
  final Set<String> _known = {};

  bool _isExpanded(String path) => !_collapsed.contains(path);

  /// On first sighting, collapse each folder — except the ancestors of the
  /// selected note, so the current note never hides inside a collapsed folder.
  void _applyDefaultCollapse(FolderNode root, String? selectedNotePath) {
    final keepOpen = _ancestorFolderPaths(selectedNotePath);
    void walk(FolderNode f) {
      if (f.path.isNotEmpty && _known.add(f.path) && !keepOpen.contains(f.path)) {
        _collapsed.add(f.path);
      }
      for (final child in f.folders) {
        walk(child);
      }
    }

    walk(root);
  }

  /// The folder paths that contain [notePath] (e.g. `A/B/n.md` -> {`A`, `A/B`}).
  Set<String> _ancestorFolderPaths(String? notePath) {
    if (notePath == null) return const {};
    final slash = notePath.lastIndexOf('/');
    if (slash < 0) return const {};
    final segments = notePath.substring(0, slash).split('/');
    final out = <String>{};
    for (var i = 0; i < segments.length; i++) {
      out.add(segments.sublist(0, i + 1).join('/'));
    }
    return out;
  }

  void _toggle(String path) => setState(() {
        if (!_collapsed.remove(path)) _collapsed.add(path);
      });

  /// Collapses (or expands) [folder] and every folder beneath it.
  void _setSubtreeCollapsed(FolderNode folder, bool collapsed) {
    void walk(FolderNode f) {
      if (collapsed) {
        _collapsed.add(f.path);
      } else {
        _collapsed.remove(f.path);
      }
      for (final child in f.folders) {
        walk(child);
      }
    }

    setState(() => walk(folder));
  }

  /// Handles a folder's menu action: collapse/expand are tree-local; everything
  /// else is delegated to the screen.
  void _onFolderAction(FolderNode folder, TreeAction action) {
    switch (action) {
      case TreeAction.collapseAll:
        _setSubtreeCollapsed(folder, true);
      case TreeAction.expandAll:
        _setSubtreeCollapsed(folder, false);
      default:
        widget.onFolderAction(folder, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _applyDefaultCollapse(widget.root, widget.selectedNotePath);
    final children = _childrenOf(widget.root, l10n);
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
    return ListView(physics: widget.physics, children: children);
  }

  List<Widget> _childrenOf(FolderNode folder, AppLocalizations l10n) => [
        for (final child in folder.folders)
          _FolderTile(
            folder: child,
            expanded: _isExpanded(child.path),
            onToggle: () => _toggle(child.path),
            menuItems: _folderMenuItems(l10n),
            menuTooltip: l10n.folderActions,
            onAction: (a) => _onFolderAction(child, a),
            onOpenNote: () => widget.onOpenFolderNote(child),
            folderNoteTooltip: _folderNoteTooltip(child, l10n),
            children: _childrenOf(child, l10n),
          ),
        for (final note in folder.notes) _noteTile(note, l10n),
      ];

  Widget _noteTile(NoteNode note, AppLocalizations l10n) {
    return Builder(
      builder: (context) {
        final tile = ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(note.title),
          selected: note.path == widget.selectedNotePath,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
          trailing: PopupMenuButton<TreeAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.noteActions,
            itemBuilder: (_) => _noteMenuItems(l10n),
            onSelected: (a) => widget.onNoteAction(note, a),
          ),
          onTap: () => widget.onNoteTap(note),
        );
        final info = _noteTooltip(context, note, l10n);
        return GestureDetector(
          onSecondaryTapDown: (details) => _showTreeMenu(
              context,
              details.globalPosition,
              _noteMenuItems(l10n),
              (a) => widget.onNoteAction(note, a)),
          child: info == null ? tile : Tooltip(message: info, child: tile),
        );
      },
    );
  }

  /// A modified-date + size tooltip for a note, from the listing metadata.
  /// Null when the backend reports neither (so no empty tooltip appears).
  String? _noteTooltip(
      BuildContext context, NoteNode note, AppLocalizations l10n) {
    final lines = _metaLines(context, l10n, note.modified, note.size);
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// The folder-note icon tooltip: the "open" hint plus the folder note's own
  /// modified date and size when available.
  String _folderNoteTooltip(FolderNode folder, AppLocalizations l10n) {
    final lines = _metaLines(
        context, l10n, folder.folderNoteModified, folder.folderNoteSize);
    return [l10n.openFolderNote, ...lines].join('\n');
  }

  /// The shared modified-date + size lines (each omitted if unknown).
  List<String> _metaLines(
    BuildContext context,
    AppLocalizations l10n,
    DateTime? modified,
    int? size,
  ) {
    final parts = <String>[];
    if (modified != null) {
      final m = MaterialLocalizations.of(context);
      final local = modified.toLocal();
      parts.add('${l10n.modifiedLabel} ${m.formatMediumDate(local)} '
          '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}');
    }
    if (size != null) parts.add(_formatSize(size));
    return parts;
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  List<PopupMenuEntry<TreeAction>> _folderMenuItems(AppLocalizations l10n) => [
        // Browsed plain folders are read-only: mutating actions are hidden, but
        // collapse/expand and reveal-in-manager still apply.
        if (widget.readOnly) ...[
          PopupMenuItem(
              value: TreeAction.collapseAll, child: Text(l10n.collapseAll)),
          PopupMenuItem(
              value: TreeAction.expandAll, child: Text(l10n.expandAll)),
          if (widget.canRevealInFileManager)
            PopupMenuItem(
              value: TreeAction.openInFileManager,
              child: Text(l10n.openInFileManager),
            ),
        ] else ...[
          PopupMenuItem(value: TreeAction.newNote, child: Text(l10n.newNote)),
          PopupMenuItem(
              value: TreeAction.newSubfolder, child: Text(l10n.newSubfolder)),
          PopupMenuItem(
              value: TreeAction.renameFolder, child: Text(l10n.renameEllipsis)),
          PopupMenuItem(
              value: TreeAction.setColor, child: Text(l10n.setColorEllipsis)),
          if (widget.canRevealInFileManager)
            PopupMenuItem(
              value: TreeAction.openInFileManager,
              child: Text(l10n.openInFileManager),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
              value: TreeAction.collapseAll, child: Text(l10n.collapseAll)),
          PopupMenuItem(
              value: TreeAction.expandAll, child: Text(l10n.expandAll)),
          const PopupMenuDivider(),
          PopupMenuItem(
              value: TreeAction.deleteFolder, child: Text(l10n.deleteFolder)),
        ],
      ];

  List<PopupMenuEntry<TreeAction>> _noteMenuItems(AppLocalizations l10n) => [
        if (widget.canRevealInFileManager)
          PopupMenuItem(
            value: TreeAction.openContainingFolder,
            child: Text(l10n.openContainingFolder),
          ),
        if (!widget.readOnly)
          PopupMenuItem(
              value: TreeAction.deleteNote, child: Text(l10n.deleteNote)),
      ];
}

/// A folder row with an explicit expand/collapse chevron beside its actions
/// menu. Expansion is controlled by the parent ([expanded] + [onToggle]) so a
/// whole subtree can be collapsed/expanded at once. The chevron matters because
/// a collapsed folder is otherwise indistinguishable from an empty one.
class _FolderTile extends StatelessWidget {
  final FolderNode folder;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  final List<PopupMenuEntry<TreeAction>> menuItems;
  final String menuTooltip;
  final void Function(TreeAction) onAction;
  final VoidCallback onOpenNote;
  final String folderNoteTooltip;

  const _FolderTile({
    required this.folder,
    required this.expanded,
    required this.onToggle,
    required this.children,
    required this.menuItems,
    required this.menuTooltip,
    required this.onAction,
    required this.onOpenNote,
    required this.folderNoteTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(folder.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Right-click anywhere on the header opens the folder menu.
        GestureDetector(
          onSecondaryTapDown: (details) => _showTreeMenu(
            context,
            details.globalPosition,
            menuItems,
            onAction,
          ),
          // Tapping the header (except the name and the menu) toggles.
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Icon(
                    // Open-folder glyph when expanded, closed when collapsed —
                    // filled variants carry the folder's accent color.
                    expanded
                        ? (color != null
                            ? Icons.folder_open
                            : Icons.folder_open_outlined)
                        : (color != null
                            ? Icons.folder
                            : Icons.folder_outlined),
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  // Fill the middle so the chevron + menu sit at a consistent
                  // right edge (and the name gets the space). Tapping the name
                  // opens the folder note; the empty area falls through to the
                  // row's toggle.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: onOpenNote,
                            behavior: HitTestBehavior.opaque,
                            child: Text(folder.name),
                          ),
                        ),
                        if (folder.hasFolderNote) ...[
                          const SizedBox(width: 6),
                          // The badge opens the folder note too (not just the
                          // name) — it's the obvious thing to tap.
                          GestureDetector(
                            onTap: onOpenNote,
                            behavior: HitTestBehavior.opaque,
                            child: Tooltip(
                              message: folderNoteTooltip,
                              child: Icon(
                                Icons.sticky_note_2_outlined,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    // expand_more points down when open, rotates to point right
                    // (→) when collapsed.
                    turns: expanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                  PopupMenuButton<TreeAction>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: menuTooltip,
                    itemBuilder: (_) => menuItems,
                    onSelected: onAction,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          alignment: Alignment.topCenter,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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
