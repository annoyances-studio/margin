// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:html2md/html2md.dart' as html2md;
import 'package:markdown/markdown.dart' as md;

/// Conversions between Markdown, HTML, and plain text — the bridge that lets
/// notes move in and out of formatting-aware apps (Word, web, OneNote).
///
/// Pure functions over strings, so they are trivially unit-testable and carry
/// no platform or clipboard dependency.

/// Renders Markdown to HTML (GitHub-flavored: tables, task lists, fenced code,
/// strikethrough). Used for "copy formatted" — Word and friends read the HTML
/// off the clipboard and rebuild the formatting.
String markdownToHtml(String markdown) =>
    md.markdownToHtml(markdown, extensionSet: md.ExtensionSet.gitHubFlavored);

/// Converts pasted HTML (from Word, a web page, OneNote, …) into Markdown, so it
/// lands in a note as `# headings`, `**bold**`, `- lists`, fenced code — the
/// migration superpower behind "paste as Markdown".
///
/// Style is pinned to Margin's own conventions (ATX `#` headings, `-` bullets,
/// fenced code) so pasted content matches what the editor writes and styles —
/// not html2md's defaults (Setext headings, `*` bullets).
String htmlToMarkdown(String html) => html2md.convert(
      html,
      styleOptions: const {
        'headingStyle': 'atx',
        'bulletListMarker': '-',
        'codeBlockStyle': 'fenced',
        'emDelimiter': '*',
        'strongDelimiter': '**',
      },
    ).trim();

/// Flattens Markdown to readable plain text (no `#`/`**`/link syntax), keeping
/// block boundaries as line breaks. Used for "copy as plain text".
String markdownToPlainText(String markdown) {
  var html = markdownToHtml(markdown);
  // Turn block ends and explicit breaks into newlines so text doesn't run
  // together once tags are removed.
  html = html
      .replaceAll(
        RegExp(r'</(p|h[1-6]|li|div|tr|blockquote|pre)>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  final stripped = html.replaceAll(RegExp(r'<[^>]+>'), '');
  return _decodeBasicEntities(stripped)
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Chooses what Markdown to insert from clipboard contents: converts [html]
/// when present (rich paste), otherwise uses [plainText] verbatim. The decision
/// behind "Paste as Markdown".
String clipboardToMarkdown({String? html, String? plainText}) =>
    (html != null && html.trim().isNotEmpty)
        ? htmlToMarkdown(html)
        : (plainText ?? '');

String _decodeBasicEntities(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&'); // ampersand last, so it doesn't double-decode
