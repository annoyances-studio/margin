// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_controller.dart';

/// The landing screen: open this device's notes folder, or (on desktop) open or
/// create a notes folder anywhere.
class OpenFolioScreen extends StatelessWidget {
  final AppController controller;

  const OpenFolioScreen({super.key, required this.controller});

  /// Folder picking via a real filesystem path only makes sense on desktop;
  /// mobile uses scoped storage (content URIs), so we offer the device folder.
  bool get _supportsFolderPicker =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tagline,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: Text(l10n.openDeviceNotes),
                onPressed: () => controller.openDeviceFolio(),
              ),
              // WebDAV works on every platform (the app speaks the protocol).
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_outlined),
                label: Text(l10n.connectWebDav),
                onPressed: () => _connectWebDav(context),
              ),
              if (_supportsFolderPicker) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(l10n.openFolio),
                  onPressed: () => _openExisting(context),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.create_new_folder),
                  label: Text(l10n.createFolio),
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

  /// Prompts for WebDAV connection details and connects. The password is held
  /// only long enough to hand to the controller, which stores it in the OS
  /// keystore — never in the Folio.
  Future<void> _connectWebDav(BuildContext context) async {
    final url = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.connectWebDav),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: l10n.serverUrl),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: user,
                decoration: InputDecoration(labelText: l10n.username),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.password),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.connect),
            ),
          ],
        );
      },
    );

    if (confirmed == true && url.text.trim().isNotEmpty) {
      // Password intentionally not trimmed (it may contain spaces).
      await controller.openWebDav(url.text.trim(), user.text.trim(), pass.text);
    }
  }

  Future<String?> _promptName(BuildContext context) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.nameFolioTitle),
          content: TextField(
            controller: field,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.folioNameLabel),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(field.text.trim()),
              child: Text(l10n.create),
            ),
          ],
        );
      },
    );
  }
}
