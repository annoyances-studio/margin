// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'markdown_preview.dart';
import 'note_editor.dart';

/// How the editor area is presented (DESIGN.md):
/// - [edit]: the inline-styled Markdown editor (default; bold renders bold,
///   headings larger, etc. while the text stays raw Markdown).
/// - [split]: that editor beside the live rendered preview.
/// - [preview]: the rendered Markdown only, read-only.
enum EditorViewMode { edit, split, preview }

/// Arranges the inline-styled editor and the rendered preview according to
/// [mode].
class NoteEditorPane extends StatelessWidget {
  final String? notePath;
  final String body;
  final ValueChanged<String> onChanged;
  final EditorViewMode mode;

  const NoteEditorPane({
    super.key,
    required this.notePath,
    required this.body,
    required this.onChanged,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    if (notePath == null) {
      return const Center(child: Text('Select a note to edit.'));
    }

    final editor = NoteEditor(
      notePath: notePath,
      body: body,
      onChanged: onChanged,
    );
    final preview = MarkdownPreview(data: body);

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
