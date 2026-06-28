// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Wraps [child] so files dragged from the OS file manager onto it are saved as
/// attachments of the open note via [onAttach] (file name + bytes).
///
/// Desktop-only — OS drag-and-drop has no equivalent on mobile, so elsewhere
/// this returns [child] untouched. While a drag hovers, a translucent overlay
/// signals whether the drop will be accepted (a note must be open).
class AttachDropTarget extends StatefulWidget {
  final Widget child;

  /// Saves one dropped file. Called once per file, in drop order.
  final Future<void> Function(String fileName, Uint8List bytes) onAttach;

  /// Whether a note is open to receive the attachment. When false, drops are
  /// ignored and the overlay says so instead of inviting a drop.
  final bool enabled;

  const AttachDropTarget({
    super.key,
    required this.child,
    required this.onAttach,
    required this.enabled,
  });

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  State<AttachDropTarget> createState() => _AttachDropTargetState();
}

class _AttachDropTargetState extends State<AttachDropTarget> {
  bool _dragging = false;

  Future<void> _onDrop(DropDoneDetails detail) async {
    setState(() => _dragging = false);
    if (!widget.enabled) return;
    for (final file in detail.files) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        await widget.onAttach(file.name, bytes);
      } catch (_) {
        // Skip an unreadable file rather than aborting the whole drop.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AttachDropTarget._isDesktop) return widget.child;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: scheme.primary.withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: Card(
                    color: scheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.enabled
                              ? Icons.attach_file
                              : Icons.block),
                          const SizedBox(width: 10),
                          Text(widget.enabled
                              ? l10n.dropToAttach
                              : l10n.dropNeedsOpenNote),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
