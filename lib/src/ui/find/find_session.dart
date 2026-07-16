// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

/// Every non-overlapping occurrence of [query] in [text], left to right, as
/// `[start, end)` character ranges. A literal (non-regex) substring search;
/// empty query or empty text yields no matches. Case-insensitive unless
/// [caseSensitive].
///
/// Pure and side-effect free so the find behaviour can be unit-tested without a
/// widget tree — the UI ([FindSession], the find bar, the editor highlight) is
/// a thin layer over this.
List<TextRange> findMatches(
  String text,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty || text.isEmpty) return const [];
  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <TextRange>[];
  var from = 0;
  while (true) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    matches.add(TextRange(start: at, end: at + needle.length));
    // Advance past this match so occurrences never overlap (e.g. "aa" in
    // "aaaa" yields two matches, not three).
    from = at + needle.length;
  }
  return matches;
}

/// Drives in-note find: holds the query, the current match set over the note
/// text, and which match is "active" (the one navigation reveals). A
/// [ChangeNotifier] so the find bar, the editor highlight, and the preview
/// scroll can all react to the same state.
///
/// The note text is fed in via [setText] (it changes as the user edits), and
/// the query via [setQuery]; both recompute the matches. Navigation ([next] /
/// [previous]) wraps around.
class FindSession extends ChangeNotifier {
  String _text = '';
  String _query = '';
  bool _caseSensitive = false;
  bool _visible = false;
  List<TextRange> _matches = const [];
  int _activeIndex = -1;

  /// Whether the find bar is showing.
  bool get isVisible => _visible;

  String get query => _query;
  bool get caseSensitive => _caseSensitive;

  List<TextRange> get matches => _matches;
  int get matchCount => _matches.length;

  /// Index of the active match, or -1 when there are none.
  int get activeIndex => _activeIndex;

  /// The active match's range, or null when there are no matches.
  TextRange? get activeMatch =>
      (_activeIndex >= 0 && _activeIndex < _matches.length)
          ? _matches[_activeIndex]
          : null;

  /// Shows the find bar (no-op if already visible). The query is preserved so
  /// reopening find keeps the last search.
  void open() {
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  /// Hides the find bar. Keeps the query but drops the active highlight so the
  /// editor stops painting matches while find is closed.
  void close() {
    if (!_visible) return;
    _visible = false;
    _matches = const [];
    _activeIndex = -1;
    notifyListeners();
  }

  /// Feeds the current note text. Called as the note changes or is edited;
  /// keeps the active match where it can (clamped) so live edits don't jump the
  /// selection around.
  void setText(String text) {
    if (text == _text) return;
    _text = text;
    _recompute(resetActive: false);
  }

  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _recompute(resetActive: true);
  }

  void setCaseSensitive(bool value) {
    if (value == _caseSensitive) return;
    _caseSensitive = value;
    _recompute(resetActive: true);
  }

  /// Moves to the next match, wrapping to the first. No-op without matches.
  void next() {
    if (_matches.isEmpty) return;
    _activeIndex = (_activeIndex + 1) % _matches.length;
    notifyListeners();
  }

  /// Moves to the previous match, wrapping to the last. No-op without matches.
  void previous() {
    if (_matches.isEmpty) return;
    _activeIndex = (_activeIndex - 1 + _matches.length) % _matches.length;
    notifyListeners();
  }

  void _recompute({required bool resetActive}) {
    if (!_visible && _query.isEmpty) {
      // Nothing to do while closed with no query.
      _matches = const [];
      _activeIndex = -1;
      notifyListeners();
      return;
    }
    _matches = findMatches(_text, _query, caseSensitive: _caseSensitive);
    if (_matches.isEmpty) {
      _activeIndex = -1;
    } else if (resetActive || _activeIndex < 0) {
      _activeIndex = 0;
    } else if (_activeIndex >= _matches.length) {
      _activeIndex = _matches.length - 1;
    }
    notifyListeners();
  }
}
