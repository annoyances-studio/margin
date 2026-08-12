// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../l10n/app_localizations.dart';
import '../../desktop/file_reveal.dart';
import '../find/find_session.dart';
import '../link_target.dart';

/// Private-use sentinels wrapped around the active find match in the source
/// before rendering, then recognised by [_MarkInlineSyntax] and painted by
/// [_HighlightBuilder]. Private-use codepoints so they never collide with real
/// note content.
const String _markOpen = '\u{E000}';
const String _markClose = '\u{E001}';

/// Renders GitHub-Flavored Markdown for the preview pane (tables, task lists,
/// strikethrough, fenced code). Read-only; editing happens in the raw pane.
///
/// Relative image links (e.g. `_attachments/pic.png`) are resolved against
/// [imageBaseDir] (the open note's folder) and loaded from disk; http(s) images
/// load from the network.
///
/// When [find] is active, the current match is highlighted in place and
/// scrolled exactly into view — the rendered Markdown has no per-character
/// geometry, so find injects a highlight span at the match's source offset
/// rather than trying to locate it after layout.
class MarkdownPreview extends StatefulWidget {
  final String data;
  final String? imageBaseDir;

  /// Scroll physics for the rendered content. The mobile preview page passes
  /// [AlwaysScrollableScrollPhysics] so pull-to-refresh works on short notes.
  final ScrollPhysics? physics;

  /// In-note find. When visible with an active match, that match is highlighted
  /// and scrolled into view.
  final FindSession? find;

  /// Opens the formatted-copy chooser ("Special Copy"). Null hides the item.
  final VoidCallback? onSpecialCopy;

  /// Follows a tapped link [target] (a sibling `.md` opens in-app, else via the
  /// OS). When null, falls back to opening the resolved target directly.
  final void Function(String target)? onOpenLink;

  /// Reads an embedded image's bytes through the backend, given its note-
  /// relative `src`. Used to render images when there's no local file on disk
  /// (browsing a remote/SAF folder). Null → such images show a broken icon.
  final Future<Uint8List?> Function(String src)? imageLoader;

  const MarkdownPreview({
    super.key,
    required this.data,
    this.imageBaseDir,
    this.physics,
    this.find,
    this.onSpecialCopy,
    this.onOpenLink,
    this.imageLoader,
  });

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  /// Key on the highlighted match widget, used to scroll it into view.
  GlobalKey? _markKey;

  /// The source offset of the match currently revealed, so we only re-scroll on
  /// actual navigation (not on every rebuild).
  int? _revealedStart;

  /// The preview's scroll. Owned so scroll-to-match is reliable — paired with
  /// [MarkdownBody] (which builds every block) so a match below the fold is
  /// still mounted and has a context to reveal.
  final ScrollController _scroll = ScrollController();

  /// Destination of the link currently hovered, shown in a status strip and
  /// used to switch the cursor to a click cursor. A [ValueNotifier] (not
  /// setState) so hovering only rebuilds the strip + the cursor region, never
  /// the Markdown itself.
  final ValueNotifier<String?> _hoveredLink = ValueNotifier(null);

  /// Anchors the render-tree walk used to find the link under the pointer.
  final GlobalKey _bodyKey = GlobalKey();

  /// Memoized backend image reads, keyed by note-relative src, so an image is
  /// fetched once and rebuilds reuse the completed future (no re-read, no
  /// flicker). Reset per note since the preview is keyed by note path.
  final Map<String, Future<Uint8List?>> _imageBytes = {};

  /// Link display-text → destination, parsed from the source (memoized per
  /// data). Links render natively (overriding the `a` builder breaks
  /// flutter_markdown's link-handler stack), so hover resolves the href by
  /// matching the hovered span's text back to the source.
  Map<String, String>? _linkHrefs;
  String? _linkHrefsForData;

  /// Last pointer position a hover hit-test ran for, to skip tiny moves.
  Offset? _lastHoverAt;

  @override
  void initState() {
    super.initState();
    widget.find?.addListener(_onFind);
  }

  @override
  void didUpdateWidget(MarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.find != widget.find) {
      oldWidget.find?.removeListener(_onFind);
      widget.find?.addListener(_onFind);
    }
  }

  @override
  void dispose() {
    widget.find?.removeListener(_onFind);
    _hoveredLink.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFind() {
    if (mounted) setState(() {});
  }

  /// Wraps the active match in sentinels so it renders highlighted. Returns null
  /// when there's nothing to highlight, or the match would cross a line/block
  /// boundary (injecting there could corrupt the Markdown structure).
  String? _highlightedData() {
    final find = widget.find;
    if (find == null || !find.isVisible) return null;
    final match = find.activeMatch;
    if (match == null) return null;
    final body = widget.data;
    final start = match.start.clamp(0, body.length);
    final end = match.end.clamp(0, body.length);
    if (start >= end) return null;
    final matched = body.substring(start, end);
    if (matched.contains('\n')) return null;
    // Inline code spans ARE highlighted (the `code` builder handles the injected
    // sentinels). Fenced blocks aren't: their text goes through a separate
    // scrollable render path where the sentinels would show literally — so skip
    // those (the match still counts, it just isn't highlighted/scrolled there).
    if (_isInsideFencedCode(body, start)) return null;
    return body.substring(0, start) +
        _markOpen +
        matched +
        _markClose +
        body.substring(end);
  }

  /// Whether [offset] sits inside a ``` fenced code block — an odd number of
  /// fences before it.
  static bool _isInsideFencedCode(String body, int offset) {
    final before = body.substring(0, offset);
    final fences =
        RegExp(r'^ {0,3}```', multiLine: true).allMatches(before).length;
    return fences.isOdd;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = widget.find?.isVisible == true ? widget.find!.activeMatch : null;
    final highlighted = _highlightedData();

    final styleSheet = _styleSheet(theme);
    var data = widget.data;
    List<md.InlineSyntax> inlineSyntaxes = const [];
    final builders = <String, MarkdownElementBuilder>{};

    if (highlighted != null && match != null) {
      // Reuse the key while the same match stays active (rebuilds keep the same
      // element); mint a new one when navigation moves to a different match.
      if (_markKey == null || match.start != _revealedStart) {
        _markKey = GlobalKey();
      }
      data = highlighted;
      final highlightColor = theme.colorScheme.tertiary.withValues(alpha: 0.60);
      inlineSyntaxes = [_MarkInlineSyntax()];
      // `mark` catches matches in normal text; `code` catches matches inside
      // inline code spans (where inline syntaxes don't run, so the sentinels
      // arrive as literal text in the element for this builder to split).
      builders['mark'] = _HighlightBuilder(_markKey!, highlightColor);
      builders['code'] = _InlineCodeBuilder(_markKey!, highlightColor);
      _scheduleReveal(match.start);
    } else {
      _markKey = null;
      _revealedStart = null;
    }

    // A subtly distinct surface tone tells the rendered preview apart from the
    // raw editor at a glance (it reads as "rendered", not "editable").
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Stack(
        children: [
          // SelectionArea gives proper cross-block text selection
          // (flutter_markdown's own `selectable:` only selects within a single
          // block), plus a place to attach the Special Copy action.
          Positioned.fill(
            child: SelectionArea(
              contextMenuBuilder: _buildSelectionMenu,
              // Cursor + hover detection live here (not per-link): a link
              // widget can't override the `a` builder without breaking
              // flutter_markdown's link handling, so we hit-test the rendered
              // text on hover instead. Over a link → click cursor + destination
              // strip; elsewhere → the text cursor. Only this region rebuilds
              // on hover (the child MarkdownBody is passed through untouched).
              child: ValueListenableBuilder<String?>(
                valueListenable: _hoveredLink,
                child: SingleChildScrollView(
                  key: _bodyKey,
                  controller: _scroll,
                  physics: widget.physics,
                  padding: const EdgeInsets.all(16),
                  // MarkdownBody (all blocks built) so a match anywhere is
                  // mounted and can be revealed.
                  child: MarkdownBody(
                    data: data,
                    selectable: false, // SelectionArea owns selection now
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                    inlineSyntaxes: inlineSyntaxes,
                    builders: builders,
                    styleSheet: styleSheet,
                    sizedImageBuilder: _buildImage,
                    onTapLink: (text, href, title) => _openLink(href),
                  ),
                ),
                builder: (context, hovered, child) => MouseRegion(
                  cursor: hovered == null
                      ? SystemMouseCursors.text
                      : SystemMouseCursors.click,
                  onHover: _onHover,
                  onExit: (_) {
                    _lastHoverAt = null;
                    _hoveredLink.value = null;
                  },
                  child: child,
                ),
              ),
            ),
          ),
          // Browser-style status strip: the hovered link's destination.
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: ValueListenableBuilder<String?>(
              valueListenable: _hoveredLink,
              builder: (context, dest, _) =>
                  dest == null ? const SizedBox.shrink() : _linkStatus(theme, dest),
            ),
          ),
        ],
      ),
    );
  }

  /// The hovered-link destination strip, aligned bottom-left and click-through.
  Widget _linkStatus(ThemeData theme, String dest) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.inverseSurface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 14, color: theme.colorScheme.onInverseSurface),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  dest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// After the highlighted match lays out, scroll it into view — but only once
  /// per navigation (guarded by [_revealedStart]).
  void _scheduleReveal(int start) {
    if (start == _revealedStart) return;
    _revealedStart = start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _markKey?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3, // ~a third down from the top: comfortable to read
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Theme-derived styles, overriding flutter_markdown's defaults where they
  /// don't adapt to the color scheme — notably the block quote, whose default
  /// is a hardcoded light-blue box that renders white-on-light-blue (i.e.
  /// unreadable) in dark mode. We use a subtle surface fill, on-surface text,
  /// and a primary accent bar instead.
  MarkdownStyleSheet _styleSheet(ThemeData theme) {
    final scheme = theme.colorScheme;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      blockquoteDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: scheme.primary, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    );
  }

  Widget _buildSelectionMenu(
    BuildContext context,
    SelectableRegionState selectableState,
  ) {
    final items = List<ContextMenuButtonItem>.from(
      selectableState.contextMenuButtonItems,
    );
    if (widget.onSpecialCopy != null) {
      items.add(ContextMenuButtonItem(
        label: AppLocalizations.of(context).specialCopy,
        onPressed: () {
          ContextMenuController.removeAny();
          widget.onSpecialCopy!();
        },
      ));
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  void _openLink(String? href) {
    if (href == null) return;
    if (widget.onOpenLink != null) {
      widget.onOpenLink!(href);
      return;
    }
    final target = resolveLinkTarget(href, widget.imageBaseDir);
    if (target != null) openWithDefaultApp(target);
  }

  /// A readable "where this goes" label for a link — the target itself (a
  /// sibling `.md` path or a URL), percent-decoded for legibility.
  String _destinationLabel(String href) {
    try {
      return Uri.decodeFull(href);
    } catch (_) {
      return href;
    }
  }

  /// On hover, resolve whether the pointer is over a link and publish its
  /// destination (drives the status strip and the cursor). Skips near-identical
  /// positions so a big note doesn't hit-test on every pixel of movement.
  void _onHover(PointerHoverEvent event) {
    final at = event.position;
    final last = _lastHoverAt;
    if (last != null && (at - last).distanceSquared < 16) return; // ~4px
    _lastHoverAt = at;
    final href = _linkAt(at);
    final label = href == null ? null : _destinationLabel(href);
    if (_hoveredLink.value != label) _hoveredLink.value = label;
  }

  /// The href of the link under the global point [global], or null. Walks the
  /// rendered paragraphs, finds the span at the point, and — if it carries a tap
  /// recognizer (i.e. it's a link) and the point is actually on its glyphs —
  /// maps its text back to the source href.
  String? _linkAt(Offset global) {
    final root = _bodyKey.currentContext?.findRenderObject();
    if (root is! RenderBox) return null;
    String? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderParagraph) {
        final local = node.globalToLocal(global);
        final size = node.size;
        if (local.dx >= 0 &&
            local.dy >= 0 &&
            local.dx <= size.width &&
            local.dy <= size.height) {
          final pos = node.getPositionForOffset(local);
          final span = node.text.getSpanForPosition(pos);
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
            // Confirm the point is horizontally over the character, not the
            // trailing space `getPositionForOffset` snapped to the nearest link
            // char. Horizontal only — a tight glyph box is shorter than the
            // line, so checking dy too made small vertical moves flicker.
            final len = node.text.toPlainText().length;
            final end = (pos.offset + 1).clamp(0, len);
            final boxes = node.getBoxesForSelection(
              TextSelection(baseOffset: pos.offset, extentOffset: end),
            );
            final onText = boxes.isEmpty ||
                boxes.any((b) {
                  final r = b.toRect();
                  return local.dx >= r.left - 2 && local.dx <= r.right + 2;
                });
            if (onText) found = _hrefForText(span.toPlainText());
          }
        }
      }
      node.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// Maps a link's display text to its source href (first match wins). Parsed
  /// from [widget.data] and memoized until the note changes.
  String? _hrefForText(String text) {
    if (_linkHrefsForData != widget.data) {
      final map = <String, String>{};
      for (final m in RegExp(r'\[([^\]\n]*)\]\(([^)\s]+)').allMatches(widget.data)) {
        map.putIfAbsent(m.group(1)!, () => m.group(2)!);
      }
      _linkHrefs = map;
      _linkHrefsForData = widget.data;
    }
    return _linkHrefs?[text];
  }

  Widget _buildImage(MarkdownImageConfig config) {
    final uri = config.uri;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(uri.toString(),
          width: config.width, height: config.height);
    }

    // Fast path: a real file on disk (local Folio / synced cache).
    final path = resolveLinkTarget(uri.path, widget.imageBaseDir);
    if (path != null) {
      return Image.file(
        File(path),
        width: config.width,
        height: config.height,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    }

    // No local file (browsing a remote/SAF folder): read the bytes through the
    // backend and render from memory.
    final loader = widget.imageLoader;
    if (loader != null) {
      final future = _imageBytes.putIfAbsent(uri.path, () => loader(uri.path));
      return _BackendImage(
        future: future,
        width: config.width,
        height: config.height,
      );
    }
    return const Icon(Icons.image_not_supported_outlined);
  }
}

/// Whether [bytes] are a Git LFS pointer stub (a tiny text file) rather than the
/// real binary — the case where a repo was cloned without LFS, so the image
/// never came down. Cheap: LFS pointers are ~130 bytes and start with a fixed
/// version line.
bool isLfsPointer(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 1024) return false;
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('version https://git-lfs.github.com/spec/v1');
}

/// Renders an image whose bytes come from the backend (no file on disk). Shows a
/// spinner while loading, an actionable hint when the "image" is really a Git
/// LFS pointer, and a broken-image icon if it can't be read/decoded.
class _BackendImage extends StatelessWidget {
  final Future<Uint8List?> future;
  final double? width;
  final double? height;

  const _BackendImage({required this.future, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width ?? 64,
            height: height ?? 64,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return const Icon(Icons.broken_image_outlined);
        }
        if (isLfsPointer(bytes)) {
          return _lfsHint(context);
        }
        return Image.memory(
          bytes,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        );
      },
    );
  }

  /// A calm, actionable stand-in for an image that's really a Git LFS pointer.
  Widget _lfsHint(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_download_outlined,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              AppLocalizations.of(context).lfsPointerImage,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recognises the [_markOpen]…[_markClose] wrapper injected around the active
/// find match and turns it into a `mark` element for [_HighlightBuilder].
class _MarkInlineSyntax extends md.InlineSyntax {
  _MarkInlineSyntax() : super('$_markOpen([\\s\\S]*?)$_markClose');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mark', match[1]!));
    return true;
  }
}

/// Renders a `mark` element as its text with a highlight background, keyed so
/// the preview can scroll it into view.
class _HighlightBuilder extends MarkdownElementBuilder {
  _HighlightBuilder(this.markKey, this.color);

  final GlobalKey markKey;
  final Color color;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = parentStyle ?? preferredStyle;
    return Text(
      element.textContent,
      key: markKey,
      style: (style ?? const TextStyle()).copyWith(backgroundColor: color),
    );
  }
}

/// Renders inline `code` spans. For the one carrying the injected sentinels it
/// paints the matched run highlighted (keyed for scroll-to-view); every other
/// code span it renders as plain code text (a rich `TextSpan` so it merges into
/// the surrounding line exactly as the default would).
class _InlineCodeBuilder extends MarkdownElementBuilder {
  _InlineCodeBuilder(this.markKey, this.color);

  final GlobalKey markKey;
  final Color color;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = preferredStyle;
    final text = element.textContent;
    final open = text.indexOf(_markOpen);
    if (open < 0) {
      // No match in this code span — render it as the default would.
      return Text.rich(TextSpan(text: text, style: style));
    }
    final close = text.indexOf(_markClose, open + _markOpen.length);
    if (close < 0) {
      return Text.rich(
        TextSpan(text: text.replaceAll(_markOpen, ''), style: style),
      );
    }
    final before = text.substring(0, open);
    final matched = text.substring(open + _markOpen.length, close);
    final after = text.substring(close + _markClose.length);
    // A keyed (non-text) wrapper so the scroll key survives inline merging.
    return Container(
      key: markKey,
      child: Text.rich(TextSpan(style: style, children: [
        if (before.isNotEmpty) TextSpan(text: before),
        TextSpan(text: matched, style: TextStyle(backgroundColor: color)),
        if (after.isNotEmpty) TextSpan(text: after),
      ])),
    );
  }
}
