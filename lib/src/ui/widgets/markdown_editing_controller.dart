// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// A [TextEditingController] that renders Markdown styling inline as you type
/// (DESIGN.md). The stored text stays raw Markdown — only its *appearance* is
/// enriched — so saving and round-trip remain exact.
///
/// This is the Flutter analogue of the old NotesWriter extending its rich-text
/// control: we extend the editing controller rather than convert documents.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return buildMarkdownTextSpan(
      text,
      base,
      linkColor: Theme.of(context).colorScheme.primary,
      // Orange table pipes stand out from blue links and read well on both
      // backgrounds (lighter on dark, deeper on light).
      tableColor: dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
    );
  }
}

/// A Markdown link or image found in the text, with its character range and
/// target. Used both for inline styling and for the editor's "open link under
/// the cursor" affordance.
class MarkdownLink {
  /// Offset of the first character of the link (the `!` for images, else `[`).
  final int start;

  /// Offset just past the closing `)`.
  final int end;

  /// The text inside `[ ]` (may be empty).
  final String label;

  /// The destination inside `( )` — a URL or a relative attachment path.
  final String target;

  /// Whether this is an image embed (`![alt](path)`) rather than a plain link.
  final bool isImage;

  const MarkdownLink({
    required this.start,
    required this.end,
    required this.label,
    required this.target,
    required this.isImage,
  });

  /// Whether the caret at [offset] sits within this link (inclusive of edges).
  bool containsOffset(int offset) => offset >= start && offset <= end;
}

/// The destination inside a link's `( )`. Allows balanced (one level of
/// nesting) parentheses, as CommonMark does — so attachment names like
/// `(本中)(AVOPVR-042)….jpg` are captured whole instead of stopping at the
/// first `)`.
const String _destination = r'(?:[^()\n]|\([^()\n]*\))*';

/// Matches `[label](target)` and `![alt](path)`: group 1 the optional `!`,
/// group 2 the label, group 3 the target.
final RegExp _linkPattern = RegExp('(!?)\\[([^\\]\\n]*)\\]\\(($_destination)\\)');

/// Finds every Markdown link/image in [text], in document order.
List<MarkdownLink> findMarkdownLinks(String text) => [
      for (final m in _linkPattern.allMatches(text))
        MarkdownLink(
          start: m.start,
          end: m.end,
          label: m.group(2)!,
          target: m.group(3)!,
          isImage: m.group(1) == '!',
        ),
    ];

/// Builds a styled [TextSpan] for [text] using [base] as the baseline style.
///
/// Invariant: the concatenation of every child span's text equals [text]
/// exactly (markers included), so the [TextField]'s cursor and selection stay
/// correct. Marker characters are dimmed; the content they wrap is styled.
TextSpan buildMarkdownTextSpan(
  String text,
  TextStyle base, {
  Color? linkColor,
  Color? tableColor,
}) {
  final link = linkColor ?? const Color(0xFF1565C0);
  final pipe = tableColor ?? const Color(0xFFE65100);
  final children = <InlineSpan>[];
  final lines = text.split('\n');
  var fenced = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final suffix = i == lines.length - 1 ? '' : '\n';

    if (line.trimLeft().startsWith('```')) {
      children.add(TextSpan(text: '$line$suffix', style: _codeStyle(base)));
      fenced = !fenced;
      continue;
    }
    if (fenced) {
      children.add(TextSpan(text: '$line$suffix', style: _codeStyle(base)));
      continue;
    }

    final lineStyle = _blockStyle(line, base);
    if (_isTableRow(line)) {
      _appendTableRow(children, line, lineStyle, link, pipe);
    } else {
      _appendInlineSpans(children, line, lineStyle, link);
    }
    if (suffix.isNotEmpty) {
      children.add(TextSpan(text: suffix, style: lineStyle));
    }
  }

  return TextSpan(style: base, children: children);
}

/// Whether [line] looks like a GFM table row — conventionally each row starts
/// with a pipe (`| a | b |`). A strong, low-false-positive signal that keeps
/// stray prose pipes ("rock | roll") from being colored.
bool _isTableRow(String line) => line.trimLeft().startsWith('|');

/// Emits a table row with its `|` separators highlighted ([pipeColor] + bold)
/// so the grid stands out, while cell text still gets normal inline styling
/// (links keep [linkColor]). Preserves the exact text (every character ends up
/// in some span).
void _appendTableRow(
  List<InlineSpan> out,
  String line,
  TextStyle lineStyle,
  Color linkColor,
  Color pipeColor,
) {
  final pipeStyle = lineStyle.copyWith(
    color: pipeColor,
    fontWeight: FontWeight.bold,
  );
  var i = 0;
  while (i < line.length) {
    if (line[i] == '|') {
      var j = i;
      while (j < line.length && line[j] == '|') {
        j++;
      }
      out.add(TextSpan(text: line.substring(i, j), style: pipeStyle));
      i = j;
    } else {
      var j = i;
      while (j < line.length && line[j] != '|') {
        j++;
      }
      _appendInlineSpans(out, line.substring(i, j), lineStyle, linkColor);
      i = j;
    }
  }
}

/// Determines the per-line block style (headings, block quotes, else base).
TextStyle _blockStyle(String line, TextStyle base) {
  final size = base.fontSize ?? 14.0;

  final heading = RegExp(r'^(#{1,6})\s').firstMatch(line);
  if (heading != null) {
    final level = heading.group(1)!.length;
    final scale = switch (level) {
      1 => 1.6,
      2 => 1.4,
      3 => 1.25,
      _ => 1.1,
    };
    return base.copyWith(
      fontSize: size * scale,
      fontWeight: FontWeight.bold,
    );
  }

  if (RegExp(r'^\s*>\s?').hasMatch(line)) {
    return base.copyWith(
      fontStyle: FontStyle.italic,
      // Dimmed to read as a quote, but not so faint it's hard to read
      // (especially under a selection highlight).
      color: base.color?.withValues(alpha: 0.85),
    );
  }

  return base;
}

TextStyle _codeStyle(TextStyle base) => base.copyWith(
      fontFamily: 'monospace',
      color: base.color?.withValues(alpha: 0.85),
    );

TextStyle _markerStyle(TextStyle base) =>
    base.copyWith(color: base.color?.withValues(alpha: 0.4));

/// Matches inline spans. Order matters: links first (so their `[]()` is not
/// mistaken for other markers), then code, bold, strikethrough, italic.
final RegExp _inlinePattern = RegExp(
  '(!?\\[[^\\]\\n]*\\]\\($_destination\\))'
  r'|(`[^`\n]+`)'
  r'|(\*\*[^*\n]+\*\*)'
  r'|(__[^_\n]+__)'
  r'|(~~[^~\n]+~~)'
  r'|(\*[^*\n]+\*)'
  r'|(_[^_\n]+_)',
);

void _appendInlineSpans(
  List<InlineSpan> out,
  String line,
  TextStyle lineStyle,
  Color linkColor,
) {
  var index = 0;
  for (final match in _inlinePattern.allMatches(line)) {
    if (match.start > index) {
      out.add(TextSpan(
        text: line.substring(index, match.start),
        style: lineStyle,
      ));
    }

    final token = match.group(0)!;
    if (match.group(1) != null) {
      _appendLinkSpans(out, token, lineStyle, linkColor);
      index = match.end;
      continue;
    }

    final (markerLength, contentStyle) = _tokenStyle(match, lineStyle);
    final content = token.substring(markerLength, token.length - markerLength);

    out
      ..add(TextSpan(
        text: token.substring(0, markerLength),
        style: _markerStyle(lineStyle),
      ))
      ..add(TextSpan(text: content, style: contentStyle))
      ..add(TextSpan(
        text: token.substring(token.length - markerLength),
        style: _markerStyle(lineStyle),
      ));

    index = match.end;
  }

  if (index < line.length) {
    out.add(TextSpan(text: line.substring(index), style: lineStyle));
  }
}

/// Splits a `[label](target)` / `![alt](path)` token into spans: the label is
/// styled as a link (coloured + underlined), the brackets and target dimmed.
/// The concatenation of the emitted spans equals [token] exactly.
void _appendLinkSpans(
  List<InlineSpan> out,
  String token,
  TextStyle lineStyle,
  Color linkColor,
) {
  final m = _linkPattern.firstMatch(token);
  if (m == null) {
    out.add(TextSpan(text: token, style: lineStyle));
    return;
  }
  final marker = _markerStyle(lineStyle);
  final labelStyle = lineStyle.copyWith(
    color: linkColor,
    decoration: TextDecoration.underline,
  );
  out
    ..add(TextSpan(text: '${m.group(1)}[', style: marker))
    ..add(TextSpan(text: m.group(2), style: labelStyle))
    ..add(TextSpan(text: '](${m.group(3)})', style: marker));
}

/// Returns (markerLength, contentStyle) for the matched inline token.
/// Group 1 is links (handled separately); here groups 2+ are the styled
/// runs: code, bold, strikethrough, italic.
(int, TextStyle) _tokenStyle(RegExpMatch match, TextStyle lineStyle) {
  if (match.group(2) != null) {
    return (1, lineStyle.copyWith(fontFamily: 'monospace'));
  }
  if (match.group(3) != null || match.group(4) != null) {
    return (2, lineStyle.copyWith(fontWeight: FontWeight.bold));
  }
  if (match.group(5) != null) {
    return (2, lineStyle.copyWith(decoration: TextDecoration.lineThrough));
  }
  // group(6) '*...*' or group(7) '_..._'
  return (1, lineStyle.copyWith(fontStyle: FontStyle.italic));
}
