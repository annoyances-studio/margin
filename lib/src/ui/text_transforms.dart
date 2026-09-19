// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Pure text transforms behind the editor's "Text tools" menu. Each maps the
// target text (a selection, or the whole document) to its transformed form.

/// Applies the transform named [action] to [s]. Unknown actions return [s].
String applyTextTool(String action, String s) => switch (action) {
      'upper' => s.toUpperCase(),
      'lower' => s.toLowerCase(),
      'proper' => _proper(s),
      'sort' => _sortLines(s),
      'noEmpty' => _removeEmptyLines(s),
      'trim' => _trimTrailing(s),
      'tabs' => s.replaceAll('\t', '  '), // two spaces
      _ => s,
    };

/// Title-case each whitespace-separated word (first letter up, rest down).
String _proper(String s) => s
    .split('\n')
    .map(
      (line) => line
          .split(' ')
          .map(
            (w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
          )
          .join(' '),
    )
    .join('\n');

/// Sort lines ascending, case-insensitive.
String _sortLines(String s) {
  final lines = s.split('\n');
  lines.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return lines.join('\n');
}

String _removeEmptyLines(String s) =>
    s.split('\n').where((l) => l.trim().isNotEmpty).join('\n');

String _trimTrailing(String s) =>
    s.split('\n').map((l) => l.replaceFirst(RegExp(r'[ \t]+$'), '')).join('\n');
