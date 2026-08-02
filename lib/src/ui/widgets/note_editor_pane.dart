// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../editor_view_mode.dart';
import '../find/find_session.dart';
import 'find_bar.dart';
import 'markdown_preview.dart';
import 'note_editor.dart';

export '../editor_view_mode.dart' show EditorViewMode;

/// Arranges the inline-styled editor and the rendered preview according to
/// [mode], and hosts in-note find (Ctrl+F): a find bar above the content, match
/// highlighting in the editor, and (since the rendered Markdown gives no
/// per-character position) an approximate scroll-to-match in the preview.
class NoteEditorPane extends StatefulWidget {
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

  /// Opens the formatted-copy chooser ("Special Copy") from the editor/preview
  /// context menus. Null hides the item.
  final VoidCallback? onSpecialCopy;

  /// Persists a pasted image as an attachment (for "Paste as Markdown").
  final Future<String?> Function(Uint8List bytes, String extension)?
      onSaveAttachment;

  /// Downloads a remote pasted image into an attachment (for "Paste as
  /// Markdown").
  final Future<String?> Function(String url)? onDownloadImage;

  /// Whether the editor soft-wraps long lines (false = horizontal scroll).
  final bool wordWrap;

  /// Read-only mode (browsed plain folders): no editing, no paste-as-markdown.
  final bool readOnly;

  /// Follows a link target (sibling `.md` in-app, else via the OS).
  final void Function(String target)? onOpenLink;

  /// Navigates back in note history. In preview mode (no text field to edit),
  /// Backspace triggers it — a reader-friendly "go back" like a browser.
  final VoidCallback? onNavigateBack;

  const NoteEditorPane({
    super.key,
    required this.notePath,
    required this.body,
    required this.onChanged,
    required this.mode,
    this.revision = 0,
    this.imageBaseDir,
    this.onSpecialCopy,
    this.onSaveAttachment,
    this.onDownloadImage,
    this.wordWrap = true,
    this.readOnly = false,
    this.onOpenLink,
    this.onNavigateBack,
  });

  @override
  State<NoteEditorPane> createState() => _NoteEditorPaneState();
}

class _NoteEditorPaneState extends State<NoteEditorPane> {
  final FindSession _find = FindSession();

  /// Focus for the pane itself. Autofocused so the Ctrl+F shortcut has a
  /// focused node in scope even before the editor is clicked, and re-focused
  /// when find closes so a repeat Ctrl+F still fires.
  final FocusNode _paneFocus = FocusNode(debugLabel: 'noteEditorPane');

  @override
  void initState() {
    super.initState();
    _find.setText(widget.body);
    _find.addListener(_onFind);
  }

  @override
  void didUpdateWidget(NoteEditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep find's text current on every update — edits, and (importantly) a
    // view-mode switch, which mounts/unmounts the editor. Without this the
    // session could keep stale text and show "No results" until re-typed.
    // (setText is a no-op when the text is unchanged.)
    _find.setText(widget.body);
  }

  @override
  void dispose() {
    _find.removeListener(_onFind);
    _find.dispose();
    _paneFocus.dispose();
    super.dispose();
  }

  void _onFind() {
    if (mounted) setState(() {}); // show/hide the bar; update the counter
  }

  void _openFind() {
    _find.setText(widget.body);
    _find.open();
  }

  void _closeFind() {
    _find.close();
    // Return focus to the pane so shortcuts keep working (the find field that
    // had focus is now gone).
    _paneFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notePath == null) {
      return Center(child: Text(AppLocalizations.of(context).selectNoteToEdit));
    }

    final editor = NoteEditor(
      key: ValueKey('${widget.notePath}#${widget.revision}'),
      notePath: widget.notePath,
      body: widget.body,
      onChanged: widget.onChanged,
      imageBaseDir: widget.imageBaseDir,
      onSpecialCopy: widget.onSpecialCopy,
      onSaveAttachment: widget.onSaveAttachment,
      onDownloadImage: widget.onDownloadImage,
      wordWrap: widget.wordWrap,
      readOnly: widget.readOnly,
      onOpenLink: widget.onOpenLink,
      find: _find,
    );
    final preview = MarkdownPreview(
      // Keyed by note (not revision) so switching notes starts a fresh preview
      // at the top, while editing the same note in split view keeps its scroll.
      key: ValueKey('preview:${widget.notePath}'),
      data: widget.body,
      imageBaseDir: widget.imageBaseDir,
      find: _find,
      onSpecialCopy: widget.onSpecialCopy,
      onOpenLink: widget.onOpenLink,
    );

    final Widget content = switch (widget.mode) {
      EditorViewMode.edit => editor,
      EditorViewMode.preview => preview,
      EditorViewMode.split => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: editor),
            const VerticalDivider(width: 1),
            Expanded(child: preview),
          ],
        ),
    };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        // Preview only (there's no text field to edit): Backspace goes back,
        // browser-style. Never bound in editor/split, where it deletes text.
        if (widget.mode == EditorViewMode.preview &&
            widget.onNavigateBack != null)
          const SingleActivator(LogicalKeyboardKey.backspace):
              widget.onNavigateBack!,
      },
      child: Focus(
        focusNode: _paneFocus,
        autofocus: true,
        child: Column(
          children: [
            if (_find.isVisible)
              FindBar(session: _find, onClose: _closeFind),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
