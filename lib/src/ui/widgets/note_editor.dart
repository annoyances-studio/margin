// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../desktop/file_reveal.dart';
import '../link_target.dart';
import 'markdown_editing_controller.dart';

/// The note editor: a text field whose Markdown is styled inline as you type
/// (headings larger, **bold** bold, `code` monospaced, [links] coloured) via
/// [MarkdownEditingController]. The stored text remains raw Markdown.
///
/// When the caret sits inside a link or image, a small affordance appears
/// offering to open it (and previewing the image, when it is one) — a touch-
/// and-desktop-consistent alternative to making links tappable in-place, which
/// fights the field's own cursor/selection gestures. On desktop, Ctrl/Cmd+click
/// on a link opens it directly without reaching for the affordance.
///
/// Resets its buffer when [notePath] changes so switching notes loads fresh
/// content without disturbing in-progress edits.
class NoteEditor extends StatefulWidget {
  final String? notePath;
  final String body;
  final ValueChanged<String> onChanged;

  /// Absolute folder of the open note, used to resolve relative attachment
  /// links for the open/preview affordance.
  final String? imageBaseDir;

  const NoteEditor({
    super.key,
    required this.notePath,
    required this.body,
    required this.onChanged,
    this.imageBaseDir,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final MarkdownEditingController _controller =
      MarkdownEditingController(text: widget.body);

  MarkdownLink? _activeLink;

  /// Whether Ctrl/Cmd is currently held — when it is, the editor shows a click
  /// cursor to signal that links can be followed (and a click opens them).
  bool _followModifierHeld = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshActiveLink);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  /// Tracks the Ctrl/Cmd modifier so the cursor can reflect "follow link" mode.
  /// Returns false so the event continues to its normal handlers.
  bool _onKeyEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final held = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (held != _followModifierHeld && mounted) {
      setState(() => _followModifierHeld = held);
    }
    return false;
  }

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
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _controller.dispose();
    super.dispose();
  }

  /// Recomputes which link (if any) the caret currently sits inside, and
  /// updates the affordance only when that changes.
  void _refreshActiveLink() {
    final selection = _controller.selection;
    MarkdownLink? found;
    if (selection.isValid) {
      final offset = selection.baseOffset;
      for (final link in findMarkdownLinks(_controller.text)) {
        if (link.containsOffset(offset)) {
          found = link;
          break;
        }
      }
    }
    if (found?.start != _activeLink?.start ||
        found?.end != _activeLink?.end ||
        found?.target != _activeLink?.target) {
      setState(() => _activeLink = found);
    }
  }

  /// Desktop: Ctrl/Cmd+click opens the link under the pointer directly. The tap
  /// itself positions the caret, so we read the link under it on the next frame
  /// (reusing the same caret-in-link logic as the affordance).
  void _handlePointerUp(PointerUpEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selection = _controller.selection;
      if (!selection.isValid) return;
      final offset = selection.baseOffset;
      for (final link in findMarkdownLinks(_controller.text)) {
        if (link.containsOffset(offset)) {
          _openLink(link);
          break;
        }
      }
    });
  }

  void _openLink(MarkdownLink link) {
    final target = resolveLinkTarget(link.target, widget.imageBaseDir);
    if (target != null && canOpenTargets) openWithDefaultApp(target);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notePath == null) {
      return const Center(child: Text('Select a note to edit.'));
    }
    final link = _activeLink;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerUp: _handlePointerUp,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                onChanged: widget.onChanged,
                // Ctrl/Cmd held → click cursor, signalling links are followable.
                mouseCursor: _followModifierHeld
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 15, height: 1.45),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Write in Markdown...',
                ),
              ),
            ),
          ),
        ),
        if (link != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _LinkAffordance(link: link, baseDir: widget.imageBaseDir),
          ),
      ],
    );
  }
}

/// A small panel shown above the editor when the caret is inside a link: an
/// image thumbnail when the target is a local image, otherwise an icon, plus
/// the link's label (or its target) and — where supported — an Open button.
///
/// Its height is capped so a failed or oversized preview can never grow to
/// cover the editor.
class _LinkAffordance extends StatelessWidget {
  final MarkdownLink link;
  final String? baseDir;

  /// Height reserved for an image preview — ~30% taller than the plain row.
  static const double _imageHeight = 72;

  const _LinkAffordance({required this.link, this.baseDir});

  @override
  Widget build(BuildContext context) {
    final external = isExternalUrl(link.target);
    final resolved = resolveLinkTarget(link.target, baseDir);
    final isImage = link.isImage || isImageTarget(link.target);
    // A local image we can attempt to render inline.
    final previewImage = isImage && !external && resolved != null;
    final canOpen = resolved != null && canOpenTargets;

    // Prefer the link's [label]; fall back to its target.
    final label = link.label.trim();
    final display = label.isNotEmpty
        ? label
        : (link.target.isEmpty ? '(no target)' : link.target);

    return Card(
      key: const Key('linkAffordance'),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Hard ceiling: the affordance is a strip, never a full-height overlay.
        constraints: const BoxConstraints(maxHeight: _imageHeight + 16),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (previewImage)
                _thumbnail(resolved)
              else
                Icon(external
                    ? Icons.open_in_new
                    : Icons.insert_drive_file_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  display,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (canOpen)
                TextButton.icon(
                  onPressed: () => openWithDefaultApp(resolved),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the image preview the same way the Preview pane does — load
  /// errors fall back to a broken-image icon via [Image.file]'s errorBuilder.
  /// The surrounding height cap keeps a failure from growing past the strip.
  Widget _thumbnail(String path) => SizedBox(
        width: 96,
        height: _imageHeight,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      );
}
