// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/widgets/markdown_editing_controller.dart';

/// Concatenates every leaf span's text, depth-first.
String _flatten(InlineSpan span) {
  final buffer = StringBuffer();
  void visit(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null) buffer.write(s.text);
      final children = s.children;
      if (children != null) children.forEach(visit);
    }
  }

  visit(span);
  return buffer.toString();
}

/// Collects the (text, style) of every leaf TextSpan that has non-null text.
List<(String, TextStyle?)> _leaves(InlineSpan span) {
  final out = <(String, TextStyle?)>[];
  void visit(InlineSpan s, TextStyle? inherited) {
    if (s is TextSpan) {
      final style = s.style ?? inherited;
      if (s.text != null) out.add((s.text!, style));
      s.children?.forEach((c) => visit(c, style));
    }
  }

  visit(span, null);
  return out;
}

void main() {
  const base = TextStyle(fontSize: 14, color: Color(0xFF000000));

  group('buildMarkdownTextSpan — invariant', () {
    test('flattened span text equals the input exactly', () {
      const samples = [
        '',
        'plain text',
        '# Heading\n\nA paragraph with **bold**, *italic*, and `code`.',
        '## H2\n- a list item\n- [ ] a task\n> a quote',
        'multi\nline\ntext\n',
        '```\nfenced code **not bold**\n```\nafter',
        'trailing newline\n',
        'tilde ~~strike~~ and _under_ here',
      ];
      for (final sample in samples) {
        final span = buildMarkdownTextSpan(sample, base);
        expect(_flatten(span), sample, reason: 'mismatch for: $sample');
      }
    });
  });

  group('buildMarkdownTextSpan — styling', () {
    test('bold content is rendered bold', () {
      final span = buildMarkdownTextSpan('a **bold** b', base);
      final bold = _leaves(span)
          .where((e) => e.$1 == 'bold' && e.$2?.fontWeight == FontWeight.bold);
      expect(bold, isNotEmpty);
    });

    test('heading lines are larger and bold', () {
      final span = buildMarkdownTextSpan('# Title', base);
      final big = _leaves(span).where((e) =>
          e.$1.contains('Title') &&
          (e.$2?.fontSize ?? 0) > 14 &&
          e.$2?.fontWeight == FontWeight.bold);
      expect(big, isNotEmpty);
    });

    test('italic content is rendered italic', () {
      final span = buildMarkdownTextSpan('an *italic* word', base);
      final italic = _leaves(span).where(
          (e) => e.$1 == 'italic' && e.$2?.fontStyle == FontStyle.italic);
      expect(italic, isNotEmpty);
    });

    test('inline code is monospaced', () {
      final span = buildMarkdownTextSpan('use `code` here', base);
      final code = _leaves(span)
          .where((e) => e.$1 == 'code' && e.$2?.fontFamily == 'monospace');
      expect(code, isNotEmpty);
    });
  });
}
