// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../editor_view_mode.dart';
import 'markdown_preview.dart';
import 'note_editor.dart';

export '../editor_view_mode.dart' show EditorViewMode;

/// Arranges the inline-styled editor and the rendered preview according to
/// [mode].
class NoteEditorPane extends StatelessWidget {
  final String? notePath;
  final String body;
  final ValueChanged<String> onChanged;
  final EditorViewMode mode;

  /// Bumped to force the editor to reload [body] (e.g. after inserting an
  /// attachment link programmatically).
  final int revision;

  /// Absolute folder of the open note, used to resolve relative image links in
  /// the preview.
  final String? imageBaseDir;

  const NoteEditorPane({
    super.key,
    required this.notePath,
    required this.body,
    required this.onChanged,
    required this.mode,
    this.revision = 0,
    this.imageBaseDir,
  });

  @override
  Widget build(BuildContext context) {
    if (notePath == null) {
      return Center(child: Text(AppLocalizations.of(context).selectNoteToEdit));
    }

    final editor = NoteEditor(
      key: ValueKey('$notePath#$revision'),
      notePath: notePath,
      body: body,
      onChanged: onChanged,
      imageBaseDir: imageBaseDir,
    );
    final preview = MarkdownPreview(data: body, imageBaseDir: imageBaseDir);

    switch (mode) {
      case EditorViewMode.edit:
        return editor;
      case EditorViewMode.preview:
        return preview;
      case EditorViewMode.split:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: editor),
            const VerticalDivider(width: 1),
            Expanded(child: preview),
          ],
        );
    }
  }
}
