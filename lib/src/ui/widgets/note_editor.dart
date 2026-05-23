// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'markdown_editing_controller.dart';

/// The note editor: a text field whose Markdown is styled inline as you type
/// (headings larger, **bold** bold, `code` monospaced) via
/// [MarkdownEditingController]. The stored text remains raw Markdown.
///
/// Resets its buffer when [notePath] changes so switching notes loads fresh
/// content without disturbing in-progress edits.
class NoteEditor extends StatefulWidget {
  final String? notePath;
  final String body;
  final ValueChanged<String> onChanged;

  const NoteEditor({
    super.key,
    required this.notePath,
    required this.body,
    required this.onChanged,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final MarkdownEditingController _controller =
      MarkdownEditingController(text: widget.body);

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload the buffer only when a different note is selected.
    if (oldWidget.notePath != widget.notePath &&
        _controller.text != widget.body) {
      _controller.text = widget.body;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notePath == null) {
      return const Center(child: Text('Select a note to edit.'));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontSize: 15, height: 1.45),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Write in Markdown...',
        ),
      ),
    );
  }
}
