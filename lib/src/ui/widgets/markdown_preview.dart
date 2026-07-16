// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
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

  const MarkdownPreview({
    super.key,
    required this.data,
    this.imageBaseDir,
    this.physics,
    this.find,
    this.onSpecialCopy,
    this.onOpenLink,
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

    var data = widget.data;
    List<md.InlineSyntax> inlineSyntaxes = const [];
    Map<String, MarkdownElementBuilder> builders = const {};

    if (highlighted != null && match != null) {
      // Reuse the key while the same match stays active (rebuilds keep the same
      // element); mint a new one when navigation moves to a different match.
      if (_markKey == null || match.start != _revealedStart) {
        _markKey = GlobalKey();
      }
      data = highlighted;
      final highlightColor = theme.colorScheme.tertiary.withValues(alpha: 0.60);
      inlineSyntaxes = [_MarkInlineSyntax()];
      builders = {
        // `mark` catches matches in normal text; `code` catches matches inside
        // inline code spans (where inline syntaxes don't run, so the sentinels
        // arrive as literal text in the element for this builder to split).
        'mark': _HighlightBuilder(_markKey!, highlightColor),
        'code': _InlineCodeBuilder(_markKey!, highlightColor),
      };
      _scheduleReveal(match.start);
    } else {
      _markKey = null;
      _revealedStart = null;
    }

    // A subtly distinct surface tone tells the rendered preview apart from the
    // raw editor at a glance (it reads as "rendered", not "editable").
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      // SelectionArea gives proper cross-block text selection (flutter_markdown's
      // own `selectable:` only selects within a single block), plus a place to
      // attach the Special Copy action.
      child: SelectionArea(
        contextMenuBuilder: _buildSelectionMenu,
        // MarkdownBody (all blocks built) inside our own scroll view, rather
        // than the scrolling Markdown (which lazily builds children) — so a
        // match anywhere in the note is mounted and can be scrolled into view.
        child: SingleChildScrollView(
          controller: _scroll,
          physics: widget.physics,
          padding: const EdgeInsets.all(16),
          child: MarkdownBody(
            data: data,
            selectable: false, // SelectionArea owns selection now
            extensionSet: md.ExtensionSet.gitHubFlavored,
            inlineSyntaxes: inlineSyntaxes,
            builders: builders,
            styleSheet: _styleSheet(theme),
            sizedImageBuilder: _buildImage,
            onTapLink: (text, href, title) => _openLink(href),
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

  Widget _buildImage(MarkdownImageConfig config) {
    final uri = config.uri;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(uri.toString(),
          width: config.width, height: config.height);
    }

    final path = resolveLinkTarget(uri.path, widget.imageBaseDir);
    if (path == null) {
      return const Icon(Icons.image_not_supported_outlined);
    }
    return Image.file(
      File(path),
      width: config.width,
      height: config.height,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
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
