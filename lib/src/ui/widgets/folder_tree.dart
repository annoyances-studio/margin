// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../content/repository_node.dart';

/// Renders the repository tree: folders as expandable tiles, notes as leaves.
class FolderTreeView extends StatelessWidget {
  final FolderNode root;
  final String? selectedNotePath;
  final String? selectedFolderPath;
  final ValueChanged<NoteNode> onNoteTap;
  final ValueChanged<FolderNode> onFolderTap;

  const FolderTreeView({
    super.key,
    required this.root,
    required this.onNoteTap,
    required this.onFolderTap,
    this.selectedNotePath,
    this.selectedFolderPath,
  });

  @override
  Widget build(BuildContext context) {
    final children = _childrenOf(root);
    if (children.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No folders yet.\nCreate a folder to start.',
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
    return ExpansionTile(
      key: PageStorageKey(folder.path),
      initiallyExpanded: true,
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name),
      backgroundColor: folder.path == selectedFolderPath
          ? Colors.transparent
          : null,
      childrenPadding: const EdgeInsets.only(left: 12),
      onExpansionChanged: (_) => onFolderTap(folder),
      children: _childrenOf(folder),
    );
  }

  Widget _noteTile(NoteNode note) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.description_outlined),
      title: Text(note.title),
      selected: note.path == selectedNotePath,
      onTap: () => onNoteTap(note),
    );
  }
}
