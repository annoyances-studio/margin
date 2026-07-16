// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/find/find_session.dart';

/// The matched substrings, for readable assertions.
List<String> _hits(String text, List<TextRange> matches) =>
    [for (final m in matches) text.substring(m.start, m.end)];

void main() {
  group('findMatches', () {
    test('empty query or empty text yields nothing', () {
      expect(findMatches('hello', ''), isEmpty);
      expect(findMatches('', 'x'), isEmpty);
    });

    test('is case-insensitive by default', () {
      final m = findMatches('Foo foo FOO', 'foo');
      expect(m.length, 3);
      expect(_hits('Foo foo FOO', m), ['Foo', 'foo', 'FOO']);
    });

    test('honours case sensitivity when asked', () {
      final m = findMatches('Foo foo FOO', 'foo', caseSensitive: true);
      expect(_hits('Foo foo FOO', m), ['foo']);
    });

    test('matches do not overlap', () {
      // "aa" in "aaaa" is two matches (0-2, 2-4), never overlapping.
      final m = findMatches('aaaa', 'aa');
      expect(m.map((r) => r.start), [0, 2]);
    });

    test('reports exact ranges', () {
      const text = 'the cat sat on the mat';
      final m = findMatches(text, 'at');
      expect(_hits(text, m), ['at', 'at', 'at']);
      expect(m.first.start, text.indexOf('at'));
    });
  });

  group('FindSession', () {
    test('recomputes on query and text, exposes count + active', () {
      final s = FindSession()..open();
      s.setText('one two one two one');
      s.setQuery('one');
      expect(s.matchCount, 3);
      expect(s.activeIndex, 0);
      expect(s.activeMatch, isNotNull);
    });

    test('next / previous wrap around', () {
      final s = FindSession()..open();
      s.setText('a a a');
      s.setQuery('a');
      expect(s.activeIndex, 0);
      s.next();
      expect(s.activeIndex, 1);
      s.next();
      s.next(); // wraps 2 -> 0
      expect(s.activeIndex, 0);
      s.previous(); // wraps 0 -> 2
      expect(s.activeIndex, 2);
    });

    test('no matches → active is -1 and navigation is a no-op', () {
      final s = FindSession()..open();
      s.setText('nothing here');
      s.setQuery('zzz');
      expect(s.matchCount, 0);
      expect(s.activeIndex, -1);
      expect(s.activeMatch, isNull);
      s.next();
      expect(s.activeIndex, -1);
    });

    test('editing the text keeps a valid active match (clamped)', () {
      final s = FindSession()..open();
      s.setText('x x x x');
      s.setQuery('x');
      s.next();
      s.next(); // active = 2
      expect(s.activeIndex, 2);
      // The note shrinks to a single match; active clamps into range.
      s.setText('x');
      expect(s.matchCount, 1);
      expect(s.activeIndex, 0);
    });

    test('changing the query resets the active match to the first', () {
      final s = FindSession()..open();
      s.setText('cat cot cut');
      s.setQuery('c');
      s.next(); // active = 1
      s.setQuery('cut');
      expect(s.activeIndex, 0);
      expect(s.matchCount, 1);
    });

    test('close clears matches; the query is retained for reopening', () {
      final s = FindSession()..open();
      s.setText('find me');
      s.setQuery('me');
      expect(s.matchCount, 1);
      s.close();
      expect(s.isVisible, isFalse);
      expect(s.matchCount, 0);
      expect(s.query, 'me');
    });

    test('notifies listeners on query change', () {
      final s = FindSession()..open();
      s.setText('abc');
      var notes = 0;
      s.addListener(() => notes++);
      s.setQuery('b');
      expect(notes, greaterThan(0));
    });
  });
}
