// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../desktop/startup_service.dart';

/// A small Settings dialog. On desktop it offers "start at login"; the section
/// hides on platforms that don't support it.
class SettingsDialog extends StatefulWidget {
  final StartupService startupService;

  const SettingsDialog({super.key, required this.startupService});

  static Future<void> show(
    BuildContext context,
    StartupService startupService,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(startupService: startupService),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _launchAtLogin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.startupService.isEnabled();
    if (!mounted) return;
    setState(() {
      _launchAtLogin = enabled;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _launchAtLogin = value);
    await widget.startupService.setEnabled(value);
    // Reflect the real state in case the platform refused the change.
    final actual = await widget.startupService.isEnabled();
    if (!mounted) return;
    setState(() => _launchAtLogin = actual);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.startupService.isSupported)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start Margin when I log in'),
                subtitle: const Text('Launch automatically at startup'),
                value: _launchAtLogin,
                onChanged: _loading ? null : _toggle,
              )
            else
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('No settings available on this platform yet.'),
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
}
