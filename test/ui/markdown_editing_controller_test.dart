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
        'a [link](https://example.com) inline',
        'an image ![alt](pics/a.png) here',
        'empty target []() and no-alt ![](b.jpg)',
        'two [one](a) and [two](b) links',
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

    test('link label is coloured and underlined; markers are not', () {
      const linkColor = Color(0xFF1565C0);
      final span = buildMarkdownTextSpan(
        'see [docs](https://x.y) now',
        base,
        linkColor: linkColor,
      );
      final label = _leaves(span).where((e) =>
          e.$1 == 'docs' &&
          e.$2?.color == linkColor &&
          e.$2?.decoration == TextDecoration.underline);
      expect(label, isNotEmpty);
      // The URL/markers are not painted in the link colour.
      final url = _leaves(span).where((e) => e.$1.contains('https://x.y'));
      expect(url.every((e) => e.$2?.color != linkColor), isTrue);
    });

    test('asterisks inside a link target are not treated as italic', () {
      final span = buildMarkdownTextSpan('[a](http://x/*b*) tail', base);
      final italic =
          _leaves(span).where((e) => e.$2?.fontStyle == FontStyle.italic);
      expect(italic, isEmpty);
    });
  });

  group('findMarkdownLinks', () {
    test('locates links and images with ranges and targets', () {
      const text = 'a [one](u1) b ![alt](pics/p.png) c';
      final links = findMarkdownLinks(text);
      expect(links.length, 2);
      expect(links[0].label, 'one');
      expect(links[0].target, 'u1');
      expect(links[0].isImage, isFalse);
      expect(text.substring(links[0].start, links[0].end), '[one](u1)');
      expect(links[1].isImage, isTrue);
      expect(links[1].target, 'pics/p.png');
      expect(text.substring(links[1].start, links[1].end), '![alt](pics/p.png)');
    });

    test('containsOffset covers the whole token inclusive of edges', () {
      final link = findMarkdownLinks('[x](y)').single;
      expect(link.containsOffset(0), isTrue);
      expect(link.containsOffset(link.end), isTrue);
      expect(link.containsOffset(link.end + 1), isFalse);
    });

    test('returns empty when there are no links', () {
      expect(findMarkdownLinks('just **bold** text'), isEmpty);
    });

    test('captures a destination with balanced parentheses', () {
      const name = '_attachments/(本中)(AVOPVR-042)超3DVR_TB_180.jpg';
      final link = findMarkdownLinks('![]($name)').single;
      expect(link.isImage, isTrue);
      expect(link.label, '');
      // The whole name is captured, not just up to the first ')'.
      expect(link.target, name);
    });

    test('a parenthesised image link round-trips through styling', () {
      const text = 'see ![x](_attachments/(a)(b)c.jpg) here';
      expect(_flatten(buildMarkdownTextSpan(text, base)), text);
    });
  });
}
