// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../desktop/startup_service.dart';
import 'app_controller.dart';
import 'editor_view_mode.dart';

/// A small Settings dialog: default-view preferences, and (on desktop) a
/// "start at login" toggle.
class SettingsDialog extends StatefulWidget {
  final StartupService startupService;
  final AppController controller;

  const SettingsDialog({
    super.key,
    required this.startupService,
    required this.controller,
  });

  static Future<void> show(
    BuildContext context, {
    required StartupService startupService,
    required AppController controller,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        startupService: startupService,
        controller: controller,
      ),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _launchAtLogin = false;
  bool _loadingStartup = true;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadStartup();
  }

  Future<void> _loadStartup() async {
    final enabled = await widget.startupService.isEnabled();
    if (!mounted) return;
    setState(() {
      _launchAtLogin = enabled;
      _loadingStartup = false;
    });
  }

  Future<void> _toggleStartup(bool value) async {
    setState(() => _launchAtLogin = value);
    await widget.startupService.setEnabled(value);
    final actual = await widget.startupService.isEnabled();
    if (!mounted) return;
    setState(() => _launchAtLogin = actual);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dropdownRow<DefaultViewPolicy>(
              label: 'Default view',
              value: controller.viewPolicy,
              items: const {
                DefaultViewPolicy.noteSpecified: 'Note specified',
                DefaultViewPolicy.editor: 'Editor',
                DefaultViewPolicy.split: 'Split',
                DefaultViewPolicy.preview: 'Preview',
              },
              onChanged: (v) async {
                await controller.setViewPolicy(v);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            _dropdownRow<EditorViewMode>(
              label: 'Default view for notes',
              value: controller.defaultNoteView,
              items: const {
                EditorViewMode.edit: 'Editor',
                EditorViewMode.split: 'Split',
                EditorViewMode.preview: 'Preview',
              },
              onChanged: (v) async {
                await controller.setDefaultNoteView(v);
                setState(() {});
              },
            ),
            const Divider(height: 28),
            if (widget.startupService.isSupported)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start Margin when I log in'),
                value: _launchAtLogin,
                onChanged: _loadingStartup ? null : _toggleStartup,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _dropdownRow<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<T>(
          value: value,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: [
            for (final entry in items.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
        ),
      ],
    );
  }
}
