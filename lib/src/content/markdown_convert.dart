// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

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

/// Replaces base64 data-URI image embeds (as pasted from Word/web) with real
/// attachments: [save] persists the decoded bytes (given a file extension) and
/// returns the new note-relative link, which is re-linked as `![Pasted Image]
/// (...)`. If [save] returns null (or the data can't be decoded), the original
/// embed is kept.
///
/// Parsed by hand with `indexOf`/`substring` rather than one big regex: a pasted
/// screenshot can be a multi-megabyte base64 payload, and a capturing group over
/// it (`([^)\s]+)`) recurses and throws a StackOverflowError — which silently
/// killed the whole paste. Scanning is linear and safe at any size.
Future<String> rewriteDataUriImages(
  String markdown,
  Future<String?> Function(Uint8List bytes, String extension) save,
) async {
  if (!markdown.contains('](data:image/')) return markdown;
  const prefix = 'data:image/';
  const b64Marker = ';base64,';
  final out = StringBuffer();
  final n = markdown.length;
  var i = 0;
  while (i < n) {
    final bang = markdown.indexOf('![', i);
    if (bang < 0) {
      out.write(markdown.substring(i));
      break;
    }
    out.write(markdown.substring(i, bang));
    // Alt text runs to the next ']' (Markdown alt can't contain one); the URL
    // must follow immediately in "(...)". base64 payloads contain no ')', so the
    // first ')' closes the link.
    final altEnd = markdown.indexOf(']', bang + 2);
    final urlEnd = (altEnd >= 0 &&
            altEnd + 1 < n &&
            markdown[altEnd + 1] == '(')
        ? markdown.indexOf(')', altEnd + 2)
        : -1;
    if (urlEnd < 0) {
      out.write('!['); // not a well-formed image; emit and move on
      i = bang + 2;
      continue;
    }
    final url = markdown.substring(altEnd + 2, urlEnd).trim();
    final original = markdown.substring(bang, urlEnd + 1);
    final b64At = url.startsWith(prefix) ? url.indexOf(b64Marker) : -1;
    if (b64At > 0) {
      final subtype = url.substring(prefix.length, b64At);
      final bytes = _tryDecodeBase64(url.substring(b64At + b64Marker.length));
      final link = bytes == null ? null : await save(bytes, _imageExt(subtype));
      out.write(link != null ? '![Pasted Image]($link)' : original);
    } else {
      out.write(original);
    }
    i = urlEnd + 1;
  }
  return out.toString();
}

final RegExp _remoteImage =
    RegExp(r'!\[([^\]]*)\]\(\s*(https?://[^)\s]+)\s*\)');

/// True if [markdown] has any remote (`http(s)`) image embed — used to decide
/// whether a paste needs the (slower, networked) download step.
bool hasRemoteImages(String markdown) => _remoteImage.hasMatch(markdown);

/// Downloads remote image embeds and re-links them to saved attachments:
/// [download] fetches+saves the image at a URL and returns the new note-relative
/// link (or null to keep the original hotlink, e.g. on timeout/404). Keeps the
/// image's alt text, falling back to "Pasted Image".
Future<String> rewriteRemoteImages(
  String markdown,
  Future<String?> Function(String url) download,
) async {
  final matches = _remoteImage.allMatches(markdown).toList();
  if (matches.isEmpty) return markdown;
  final out = StringBuffer();
  var last = 0;
  for (final m in matches) {
    out.write(markdown.substring(last, m.start));
    final link = await download(m.group(2)!);
    if (link == null) {
      out.write(m.group(0)); // keep the original link on failure
    } else {
      final alt = m.group(1)!.trim();
      out.write('![${alt.isEmpty ? 'Pasted Image' : alt}]($link)');
    }
    last = m.end;
  }
  out.write(markdown.substring(last));
  return out.toString();
}

final RegExp _htmlImg =
    RegExp(r'<img\b[^>]*?\bsrc="([^"]*)"[^>]*>', caseSensitive: false);

/// Inlines local image sources in [html] as base64 data URIs so the HTML is
/// self-contained (e.g. when pasting into Word, which can't read local paths).
/// [read] returns the bytes for a (non-http, non-data) src, or null to leave it
/// as-is. Used by "Copy formatted".
Future<String> embedHtmlImages(
  String html,
  Future<Uint8List?> Function(String src) read,
) async {
  final matches = _htmlImg.allMatches(html).toList();
  if (matches.isEmpty) return html;
  final out = StringBuffer();
  var last = 0;
  for (final m in matches) {
    out.write(html.substring(last, m.start));
    final tag = m.group(0)!;
    final src = m.group(1)!;
    Uint8List? bytes;
    if (!src.startsWith('http') && !src.startsWith('data:')) {
      bytes = await read(src);
    }
    if (bytes == null) {
      out.write(tag);
    } else {
      final dataUri =
          'data:${_mimeForExt(_extFromPath(src))};base64,${base64.encode(bytes)}';
      out.write(tag.replaceFirst('src="$src"', 'src="$dataUri"'));
    }
    last = m.end;
  }
  out.write(html.substring(last));
  return out.toString();
}

Uint8List? _tryDecodeBase64(String data) {
  try {
    return base64.decode(data.replaceAll(RegExp(r'\s'), ''));
  } catch (_) {
    return null;
  }
}

String _imageExt(String mimeSubtype) {
  switch (mimeSubtype.toLowerCase()) {
    case 'jpeg':
    case 'jpg':
      return 'jpg';
    case 'svg+xml':
      return 'svg';
    default:
      return mimeSubtype.toLowerCase(); // png, gif, webp, bmp, …
  }
}

String _extFromPath(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
}

String _mimeForExt(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'svg':
      return 'image/svg+xml';
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
      return 'image/$ext';
    default:
      return 'application/octet-stream';
  }
}

String _decodeBasicEntities(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&'); // ampersand last, so it doesn't double-decode
