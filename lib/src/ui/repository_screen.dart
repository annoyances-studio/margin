// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'widgets/folder_tree.dart';
import 'widgets/note_editor.dart';

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
            title: Text(controller.repositoryName),
            actions: [
              IconButton(
                tooltip: 'New folder',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _promptNewFolder,
              ),
              IconButton(
                tooltip: 'New note',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: _promptNewNote,
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

  Widget _body() {
    final tree = controller.tree;
    final editor = NoteEditor(
      notePath: controller.selectedNotePath,
      body: controller.workingBody,
      onChanged: controller.updateBody,
    );

    if (!_showTree || tree == null) {
      return editor;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: FolderTreeView(
            root: tree,
            selectedNotePath: controller.selectedNotePath,
            selectedFolderPath: controller.selectedFolderPath,
            onNoteTap: controller.selectNote,
            onFolderTap: (folder) => controller.selectFolder(folder.path),
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

  Future<void> _promptNewFolder() async {
    final name = await _promptName(
      title: 'New folder',
      label: 'Folder name',
    );
    if (name != null && name.isNotEmpty) {
      await controller.createFolder(name);
    }
  }

  Future<void> _promptNewNote() async {
    final folder = controller.selectedFolderPath;
    if (folder == null || folder.isEmpty) {
      _showMessage('Select a folder first — notes cannot live at the root.');
      return;
    }
    final name = await _promptName(title: 'New note', label: 'Note name');
    if (name != null && name.isNotEmpty) {
      await controller.createNote(name);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
