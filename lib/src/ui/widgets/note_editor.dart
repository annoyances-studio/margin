// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../content/markdown_convert.dart';
import '../../desktop/file_reveal.dart';
import '../clipboard_service.dart';
import '../find/find_session.dart';
import '../link_target.dart';
import 'go_to_line_bar.dart';
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

  /// Clipboard access for "Paste as Markdown". Injectable so tests use a fake;
  /// defaults (null) to the platform clipboard resolved in the state.
  final ClipboardService? clipboard;

  /// Opens the formatted-copy chooser ("Special Copy"). Null hides the item.
  final VoidCallback? onSpecialCopy;

  /// Persists a pasted image as an attachment, returning its note-relative link.
  /// When provided, base64 images pasted via "Paste as Markdown" are saved as
  /// files instead of being inlined into the note.
  final Future<String?> Function(Uint8List bytes, String extension)?
      onSaveAttachment;

  /// Downloads a remote pasted image and saves it as an attachment, returning
  /// its note-relative link (null to keep the original hotlink). When provided,
  /// remote images pasted via "Paste as Markdown" are localized.
  final Future<String?> Function(String url)? onDownloadImage;

  /// When false, long lines run off the right edge with a horizontal scrollbar
  /// instead of soft-wrapping — easier to read wide tables and code.
  final bool wordWrap;

  /// Read-only mode (browsed plain folders): the text can be selected and
  /// copied but not edited, and "Paste as Markdown" is hidden.
  final bool readOnly;

  /// Follows a link [target] (a sibling `.md` opens in-app, else via the OS).
  /// When null, the editor falls back to opening the resolved target directly.
  final void Function(String target)? onOpenLink;

  /// In-note find (Ctrl+F). When non-null, matches are highlighted in the field
  /// and the active match is scrolled into view. The editor also feeds its live
  /// text to the session so matches track edits.
  final FindSession? find;

  /// Go-to-line (Ctrl+G). When it fires, the editor moves the caret to that line
  /// and focuses, so the field scrolls it exactly into view.
  final GoToLineRequest? goToLine;

  const NoteEditor({
    super.key,
    required this.notePath,
    required this.body,
    required this.onChanged,
    this.imageBaseDir,
    this.clipboard,
    this.onSpecialCopy,
    this.onSaveAttachment,
    this.onDownloadImage,
    this.wordWrap = true,
    this.readOnly = false,
    this.onOpenLink,
    this.find,
    this.goToLine,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final MarkdownEditingController _controller =
      MarkdownEditingController(text: widget.body);

  /// The injected clipboard, or the platform default.
  late final ClipboardService _clipboard =
      widget.clipboard ?? createClipboardService();

  /// Focus for the text field, so go-to-line can focus it and let the field
  /// reveal the caret (an exact scroll, no measuring).
  final FocusNode _fieldFocus = FocusNode();

  /// Caret line/column (1-based), shown in a small pill. A [ValueNotifier] so
  /// moving the caret updates only the pill, not the whole editor.
  final ValueNotifier<({int line, int col})?> _caret = ValueNotifier(null);

  MarkdownLink? _activeLink;

  /// Whether Ctrl/Cmd is currently held — when it is, the editor shows a click
  /// cursor to signal that links can be followed (and a click opens them).
  bool _followModifierHeld = false;

  /// Horizontal scroll position for the no-wrap layout.
  final ScrollController _hScroll = ScrollController();

  /// The field's own vertical scroll — owned here so find can reveal a match
  /// without stealing focus from the find bar.
  final ScrollController _vScroll = ScrollController();

  /// Last measured wrap-mode text width, used to lay out an off-screen painter
  /// that locates a match's vertical position for scroll-to-reveal.
  double _viewportWidth = 0;

  /// Cached layout for scroll-to-reveal, reused across next/prev while the text
  /// and width are unchanged so rapid navigation stays responsive.
  TextPainter? _revealPainter;
  String? _revealPainterText;
  double? _revealPainterWidth;
  TextScaler? _revealPainterScaler;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onEditorChanged);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    widget.find?.addListener(_onFind);
    widget.goToLine?.addListener(_onGoToLine);
    // Apply any highlights the session already holds (find opened before this
    // editor mounted, e.g. switching notes with find active).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onFind();
    });
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
    if (oldWidget.find != widget.find) {
      oldWidget.find?.removeListener(_onFind);
      widget.find?.addListener(_onFind);
      _onFind();
    }
    if (oldWidget.goToLine != widget.goToLine) {
      oldWidget.goToLine?.removeListener(_onGoToLine);
      widget.goToLine?.addListener(_onGoToLine);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    widget.find?.removeListener(_onFind);
    widget.goToLine?.removeListener(_onGoToLine);
    _revealPainter?.dispose();
    _caret.dispose();
    _fieldFocus.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Fires on every text/selection change: keeps the link affordance current,
  /// updates the caret pill, and feeds the live text to find so matches track
  /// edits precisely.
  void _onEditorChanged() {
    _refreshActiveLink();
    _updateCaret();
    widget.find?.setText(_controller.text);
  }

  /// Recomputes the 1-based caret line/column from the selection's base offset.
  void _updateCaret() {
    final selection = _controller.selection;
    if (!selection.isValid) {
      _caret.value = null;
      return;
    }
    final text = _controller.text;
    final offset = selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, offset);
    final lastNewline = before.lastIndexOf('\n');
    _caret.value = (
      line: '\n'.allMatches(before).length + 1,
      col: offset - lastNewline, // lastNewline is -1 when on line 1 → col = offset+1
    );
  }

  /// Jumps to the requested 1-based line: selects that line and focuses the
  /// field so it scrolls the caret exactly into view. Works read-only too (a
  /// read-only field is still selectable), so it serves companion browsing.
  void _onGoToLine() {
    final line = widget.goToLine?.line;
    if (line == null || line <= 0 || !mounted) return;
    final lines = _controller.text.split('\n');
    final n = line.clamp(1, lines.length);
    var offset = 0;
    for (var i = 0; i < n - 1; i++) {
      offset += lines[i].length + 1; // + the newline
    }
    final end = offset + lines[n - 1].length;
    // Focus so the caret is live (arrow keys work), and select the line with
    // its caret (extent) at the start. Then do our deterministic scroll in a
    // post-frame so it runs after the field's own caret-reveal and wins — the
    // line lands ~30% down rather than jammed against an edge.
    _fieldFocus.requestFocus();
    _controller.selection = TextSelection(baseOffset: end, extentOffset: offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealOffset(offset);
    });
  }

  /// Reacts to find state: repaint the field's match highlights and reveal the
  /// active match. Setting highlights never touches the stored text.
  void _onFind() {
    final session = widget.find;
    if (session == null) return;
    _controller.setHighlights(session.matches, session.activeIndex);
    _revealActive();
  }

  /// Scrolls the field so the active match is on screen, without requiring the
  /// field to have focus (find keeps it). Locates the match by laying out an
  /// off-screen painter with the same styled spans and width the field uses —
  /// an approximation that is more than good enough to bring the line into view.
  ///
  /// The painter is cached (text + width don't change while navigating), so
  /// rapid next/prev stays responsive; and the target is deterministic (the
  /// match always lands ~30% down) rather than "skip if already visible", which
  /// made fast navigation feel like it wasn't keeping up.
  void _revealActive() {
    final match = widget.find?.activeMatch;
    if (match == null) return;
    _revealOffset(match.start);
  }

  /// Scrolls the field so the character at [offset] is ~30% down the viewport,
  /// without requiring focus. Shared by find's active-match reveal and go-to-
  /// line. Locates the position with an off-screen painter matched to the
  /// field's base style + text scaler (a mismatch wraps differently and drifts).
  /// The painter is cached (text + width unchanged between calls) so repeated
  /// reveals stay responsive.
  void _revealOffset(int offset) {
    if (!mounted) return;
    if (!_vScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealOffset(offset);
      });
      return;
    }
    final text = _controller.text;
    final width =
        (widget.wordWrap && _viewportWidth > 0) ? _viewportWidth : double.infinity;
    final scaler = MediaQuery.textScalerOf(context);
    if (_revealPainter == null ||
        _revealPainterText != text ||
        _revealPainterWidth != width ||
        _revealPainterScaler != scaler) {
      final base = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
          .merge(const TextStyle(fontSize: 15, height: 1.45));
      _revealPainter?.dispose();
      _revealPainter = TextPainter(
        text: buildMarkdownTextSpan(text, base),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: width);
      _revealPainterText = text;
      _revealPainterWidth = width;
      _revealPainterScaler = scaler;
    }
    final start = offset.clamp(0, text.length);
    final dy =
        _revealPainter!.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy;
    final pos = _vScroll.position;
    final viewport = pos.viewportDimension;
    final target = (dy - viewport * 0.3).clamp(0.0, pos.maxScrollExtent);
    _vScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
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
    if (widget.onOpenLink != null) {
      widget.onOpenLink!(link.target);
      return;
    }
    final target = resolveLinkTarget(link.target, widget.imageBaseDir);
    if (target != null && canOpenTargets) openWithDefaultApp(target);
  }

  /// Reads the clipboard's HTML (from Word, the web, OneNote, …), converts it to
  /// Markdown, and inserts it at the caret — the migration/"paste rich content
  /// as markdown" path. Falls back to the clipboard's plain text when there is
  /// no HTML. (Plain Ctrl+V still pastes verbatim via the default menu item.)
  ///
  /// A clipboard holding *only* an image (the screenshot case — the OS paste
  /// rejects it because the field is text-only) is attached and linked instead.
  /// HTML keeps priority: copies from Word/browsers carry HTML alongside any
  /// bitmap rendering, and the HTML is the faithful version.
  Future<void> _pasteAsMarkdown() async {
    final html = await _clipboard.readHtml();
    if (html == null) {
      final image = await _clipboard.readImage();
      final saver = widget.onSaveAttachment;
      if (image != null && saver != null) {
        final link = await saver(image.bytes, image.extension);
        if (link != null) _insertAtCaret('![Pasted Image]($link)');
        return;
      }
    }
    var inserted = clipboardToMarkdown(
      html: html,
      plainText: await _clipboard.readText(),
    );
    // Turn any pasted base64 images into real attachments (linked as
    // "[Pasted Image]") rather than bloating the note with data URIs.
    final saver = widget.onSaveAttachment;
    if (saver != null) inserted = await rewriteDataUriImages(inserted, saver);

    // Download remote (hotlinked) images into attachments so they don't rot.
    // This can be slow, so show progress; failures keep the original link.
    final downloader = widget.onDownloadImage;
    if (downloader != null && mounted && hasRemoteImages(inserted)) {
      final messenger = ScaffoldMessenger.of(context);
      final progress = messenger.showSnackBar(SnackBar(
        duration: const Duration(minutes: 5),
        content: Row(children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(AppLocalizations.of(context).downloadingImages),
        ]),
      ));
      try {
        inserted = await rewriteRemoteImages(inserted, downloader);
      } finally {
        progress.close();
      }
    }
    _insertAtCaret(inserted);
  }

  /// Replaces the selection (or inserts at the caret / end) with [inserted]
  /// and reports the change.
  void _insertAtCaret(String inserted) {
    if (inserted.isEmpty || !mounted) return;

    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final updated = text.replaceRange(start, end, inserted);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
    widget.onChanged(updated);
  }

  /// The editing field itself. Shared by the wrapped and no-wrap layouts.
  Widget _editorField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      key: const Key('noteEditorField'),
      controller: _controller,
      focusNode: _fieldFocus,
      scrollController: _vScroll,
      onChanged: widget.onChanged,
      readOnly: widget.readOnly,
      // Ctrl/Cmd held → click cursor, signalling links are followable.
      mouseCursor: _followModifierHeld
          ? SystemMouseCursors.click
          : SystemMouseCursors.text,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontSize: 15, height: 1.45),
      // Add "Paste as Markdown" to the selection toolbar alongside the
      // default actions (which keep pasting verbatim) — but not when read-only.
      contextMenuBuilder: (context, editableState) {
        final l10n = AppLocalizations.of(context);
        final items = List<ContextMenuButtonItem>.from(
          editableState.contextMenuButtonItems,
        );
        if (!widget.readOnly) {
          items.add(ContextMenuButtonItem(
            label: l10n.pasteAsMarkdown,
            onPressed: () {
              ContextMenuController.removeAny();
              _pasteAsMarkdown();
            },
          ));
        }
        if (widget.onSpecialCopy != null) {
          items.add(ContextMenuButtonItem(
            label: l10n.specialCopy,
            onPressed: () {
              ContextMenuController.removeAny();
              widget.onSpecialCopy!();
            },
          ));
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableState.contextMenuAnchors,
          buttonItems: items,
        );
      },
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: l10n.writeInMarkdown,
      ),
    );
  }

  /// No-wrap layout: the field is sized to its widest line and scrolls
  /// horizontally, so long table rows and code stay on one line.
  Widget _noWrapEditor(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _noWrapWidth(constraints.maxWidth);
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, child: _editorField(context)),
          ),
        );
      },
    );
  }

  /// Width for the no-wrap field: the widest line (measured exactly for the few
  /// longest by character count — a cheap, good-enough proxy), but never less
  /// than the viewport so short notes behave normally. Plus a small cushion for
  /// the caret and proportional-font slack.
  double _noWrapWidth(double available) {
    final lines = _controller.text.split('\n')
      ..sort((a, b) => b.length.compareTo(a.length));
    const style = TextStyle(fontSize: 15, height: 1.45);
    var widest = 0.0;
    for (final line in lines.take(5)) {
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (tp.width > widest) widest = tp.width;
    }
    final wanted = widest + 24;
    return wanted < available ? available : wanted;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.notePath == null) {
      return Center(child: Text(
        widget.readOnly ? l10n.selectNoteToRead : l10n.selectNoteToEdit,
      ));
    }
    final link = _activeLink;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerUp: _handlePointerUp,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: widget.wordWrap
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        // Remember the wrap width so find can locate a match's
                        // vertical position off-screen for scroll-to-reveal.
                        _viewportWidth = constraints.maxWidth;
                        return _editorField(context);
                      },
                    )
                  : _noWrapEditor(context),
            ),
          ),
        ),
        if (link != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _LinkAffordance(
              link: link,
              baseDir: widget.imageBaseDir,
              onOpenLink: widget.onOpenLink,
            ),
          ),
        // Caret line/column pill, bottom-right. Hidden while the link affordance
        // occupies the bottom strip (it takes priority).
        if (link == null)
          Positioned(
            right: 8,
            bottom: 8,
            child: IgnorePointer(
              child: ValueListenableBuilder<({int line, int col})?>(
                valueListenable: _caret,
                builder: (context, caret, _) =>
                    caret == null ? const SizedBox.shrink() : _caretPill(context, caret),
              ),
            ),
          ),
      ],
    );
  }

  Widget _caretPill(BuildContext context, ({int line, int col}) caret) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        AppLocalizations.of(context).lineColumn(caret.line, caret.col),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onInverseSurface,
        ),
      ),
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
  final void Function(String target)? onOpenLink;

  /// Height reserved for an image preview — ~30% taller than the plain row.
  static const double _imageHeight = 72;

  const _LinkAffordance({required this.link, this.baseDir, this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final external = isExternalUrl(link.target);
    final resolved = resolveLinkTarget(link.target, baseDir);
    final isImage = link.isImage || isImageTarget(link.target);
    // A local image we can attempt to render inline.
    final previewImage = isImage && !external && resolved != null;
    final canOpen = resolved != null && canOpenTargets;
    // A local file (attachment): offer "reveal in folder" so the user can pick
    // or edit the actual file, not just open it in a viewer.
    final canReveal = resolved != null && !external && canRevealInFileManager;

    // Prefer the link's [label]; fall back to its target.
    final label = link.label.trim();
    final display = label.isNotEmpty
        ? label
        : (link.target.isEmpty ? l10n.noTarget : link.target);

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
              if (canReveal)
                IconButton(
                  tooltip: l10n.openContainingFolder,
                  onPressed: () =>
                      revealInFileManager(resolved, selectFile: true),
                  icon: const Icon(Icons.folder_open, size: 18),
                ),
              if (canOpen)
                TextButton.icon(
                  onPressed: () => onOpenLink != null
                      ? onOpenLink!(link.target)
                      : openWithDefaultApp(resolved),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l10n.open),
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
