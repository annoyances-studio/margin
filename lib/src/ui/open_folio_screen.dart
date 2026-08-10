// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../storage/onedrive_auth.dart';
import 'app_controller.dart';

/// The landing screen: a primary "open this device's notes" button for the
/// user who just wants to take notes, an "Open a Folio" button that unfolds
/// the open/create/connect options, and the recently opened Folios.
class OpenFolioScreen extends StatefulWidget {
  final AppController controller;

  const OpenFolioScreen({super.key, required this.controller});

  @override
  State<OpenFolioScreen> createState() => _OpenFolioScreenState();
}

class _OpenFolioScreenState extends State<OpenFolioScreen> {
  AppController get controller => widget.controller;

  /// Whether the "Open a Folio" options are unfolded.
  bool _showOpenOptions = false;

  @override
  void initState() {
    super.initState();
    // Repaint on controller changes (recents loading/removal, busy, errors) —
    // the screen shows that state, so it can't rely on a parent rebuilding it.
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Folder picking via a real filesystem path only makes sense on desktop;
  /// mobile uses scoped storage (content URIs), so we offer the device folder.
  bool get _supportsFolderPicker =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Android reads a user-granted folder read-only via SAF (companion mode);
  /// desktop uses the folder picker above, so this button is Android-only.
  bool get _supportsSafFolder => !kIsWeb && Platform.isAndroid;

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
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: Icon(_showOpenOptions
                    ? Icons.expand_less
                    : Icons.expand_more),
                label: Text(l10n.openFolio),
                onPressed: () =>
                    setState(() => _showOpenOptions = !_showOpenOptions),
              ),
              if (_showOpenOptions) ..._openOptions(context, l10n),
              ..._recentSection(context, l10n),
              if (controller.syncProgress != null) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: controller.syncProgress!.total == 0
                      ? null
                      : controller.syncProgress!.completed /
                          controller.syncProgress!.total,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.syncing(
                    controller.syncProgress!.completed,
                    controller.syncProgress!.total,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else if (controller.isBusy) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
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

  /// The unfolded "Open a Folio" choices: local open/create (desktop only —
  /// mobile has no folder picker) and the remote connects. OneDrive stays
  /// gated on the build-time client id + redirect URI being configured (so
  /// non-OneDrive builds don't show a dead button).
  List<Widget> _openOptions(BuildContext context, AppLocalizations l10n) => [
        if (_supportsFolderPicker) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(l10n.openExistingFolio),
            onPressed: () => _openExisting(context),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.create_new_folder),
            label: Text(l10n.createFolioLocal),
            onPressed: () => _createNew(context),
          ),
        ],
        if (_supportsSafFolder) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_special_outlined),
            label: Text(l10n.openFolderToRead),
            onPressed: () => controller.browseAndroidFolder(),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.cloud_outlined),
          label: Text(l10n.connectWebDav),
          onPressed: () => _connectWebDav(context),
        ),
        if (OneDriveAuth.isConfiguredFromEnv) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud_queue_outlined),
            label: Text(l10n.connectOneDrive),
            onPressed: () => _connectOneDrive(context),
          ),
        ],
      ];

  /// The recently opened Folios (device notes never appear — it has its own
  /// button above). Tap to reopen; the X forgets the entry.
  List<Widget> _recentSection(BuildContext context, AppLocalizations l10n) {
    final recents = controller.recentFolios;
    if (recents.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      Text(
        l10n.recentFolios,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      for (final recent in recents)
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          leading: Icon(_recentIcon(recent.type)),
          title: Text(recent.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(recent.location, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.removeFromRecent,
            onPressed: () => controller.removeRecentFolio(recent),
          ),
          onTap: () => controller.openRecentFolio(recent),
        ),
    ];
  }

  static IconData _recentIcon(String type) => switch (type) {
        'webdav' => Icons.cloud_outlined,
        'onedrive' => Icons.cloud_queue_outlined,
        _ => Icons.folder_outlined,
      };

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
    var browse = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l10n.connectWebDav),
            content: SizedBox(
              width: 340,
              child: Column(
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
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: browse,
                    onChanged: (v) => setState(() => browse = v ?? false),
                    title: Text(l10n.browseReadOnly),
                    subtitle: Text(l10n.browseReadOnlyHelp),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(browse ? l10n.openFolio : l10n.connect),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && url.text.trim().isNotEmpty) {
      // Password intentionally not trimmed (it may contain spaces).
      if (browse) {
        await controller.browseWebDav(
            url.text.trim(), user.text.trim(), pass.text);
      } else {
        await controller.openWebDav(
            url.text.trim(), user.text.trim(), pass.text);
      }
    }
  }

  /// Connects a OneDrive Folio: sign in (system browser) if needed, ask which
  /// folder to use, then open/create a Folio there through the local cache. The
  /// access token is held in the OS keystore by the controller — never here.
  Future<void> _connectOneDrive(BuildContext context) async {
    final signedIn = await controller.signInOneDrive();
    if (!signedIn || !context.mounted) return; // error surfaces via the screen

    final choice = await _promptOneDriveFolder(context);
    if (choice == null) return;
    if (choice.browse) {
      await controller.browseOneDrive(choice.folder);
    } else {
      await controller.openOneDrive(choice.folder, name: choice.name);
    }
  }

  /// Asks for the OneDrive folder and (for a managed Folio) its name, or a
  /// read-only browse. A typed path keeps the PoC simple; a visual folder
  /// browser can come later.
  Future<({String folder, String name, bool browse})?> _promptOneDriveFolder(
    BuildContext context,
  ) {
    final folder = TextEditingController(text: 'Apps/Margin/Notes');
    final name = TextEditingController(text: 'My Notes');
    var browse = false;
    return showDialog<({String folder, String name, bool browse})>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l10n.connectOneDrive),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: folder,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l10n.oneDriveFolderLabel,
                      helperText: l10n.oneDriveFolderHelp,
                    ),
                  ),
                  // The name only applies to a managed Folio.
                  if (!browse) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: name,
                      decoration:
                          InputDecoration(labelText: l10n.folioNameLabel),
                    ),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: browse,
                    onChanged: (v) => setState(() => browse = v ?? false),
                    title: Text(l10n.browseReadOnly),
                    subtitle: Text(l10n.browseReadOnlyHelp),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final f = folder.text.trim();
                  if (f.isEmpty) return;
                  Navigator.of(context).pop((
                    folder: f,
                    name: name.text.trim().isEmpty
                        ? 'My Notes'
                        : name.text.trim(),
                    browse: browse,
                  ));
                },
                child: Text(browse ? l10n.openFolio : l10n.connect),
              ),
            ],
          ),
        );
      },
    );
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
