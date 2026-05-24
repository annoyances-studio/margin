// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';

/// The landing screen: open this device's notes folder, or (on desktop) open or
/// create a notes folder anywhere.
class OpenRepositoryScreen extends StatelessWidget {
  final AppController controller;

  const OpenRepositoryScreen({super.key, required this.controller});

  /// Folder picking via a real filesystem path only makes sense on desktop;
  /// mobile uses scoped storage (content URIs), so we offer the device folder.
  bool get _supportsFolderPicker =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Margin',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Plain Markdown notes in a folder you control.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: const Text("Open this device's notes"),
                onPressed: () => controller.openDeviceRepository(),
              ),
              if (_supportsFolderPicker) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open a notes folder'),
                  onPressed: () => _openExisting(context),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('Create a new notes folder'),
                  onPressed: () => _createNew(context),
                ),
              ],
              if (controller.error != null) ...[
                const SizedBox(height: 24),
                Text(
                  controller.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExisting(BuildContext context) async {
    final path = await getDirectoryPath();
    if (path != null) {
      await controller.openPath(path);
    }
  }

  Future<void> _createNew(BuildContext context) async {
    final path = await getDirectoryPath();
    if (path == null) return;
    if (!context.mounted) return;

    final name = await _promptName(context);
    if (name != null && name.isNotEmpty) {
      await controller.createPath(path, name);
    }
  }

  Future<String?> _promptName(BuildContext context) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Name this repository'),
          content: TextField(
            controller: field,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Repository name'),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(field.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}
