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
    return buildMarkdownTextSpan(text, base);
  }
}

/// Builds a styled [TextSpan] for [text] using [base] as the baseline style.
///
/// Invariant: the concatenation of every child span's text equals [text]
/// exactly (markers included), so the [TextField]'s cursor and selection stay
/// correct. Marker characters are dimmed; the content they wrap is styled.
TextSpan buildMarkdownTextSpan(String text, TextStyle base) {
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
    _appendInlineSpans(children, line, lineStyle, base);
    if (suffix.isNotEmpty) {
      children.add(TextSpan(text: suffix, style: lineStyle));
    }
  }

  return TextSpan(style: base, children: children);
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
      color: base.color?.withValues(alpha: 0.7),
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

/// Matches inline spans. Order matters: code, bold, strikethrough, italic.
final RegExp _inlinePattern = RegExp(
  r'(`[^`\n]+`)'
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
  TextStyle base,
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

/// Returns (markerLength, contentStyle) for the matched inline token.
(int, TextStyle) _tokenStyle(RegExpMatch match, TextStyle lineStyle) {
  if (match.group(1) != null) {
    return (1, lineStyle.copyWith(fontFamily: 'monospace'));
  }
  if (match.group(2) != null || match.group(3) != null) {
    return (2, lineStyle.copyWith(fontWeight: FontWeight.bold));
  }
  if (match.group(4) != null) {
    return (2, lineStyle.copyWith(decoration: TextDecoration.lineThrough));
  }
  // group(5) '*...*' or group(6) '_..._'
  return (1, lineStyle.copyWith(fontStyle: FontStyle.italic));
}
