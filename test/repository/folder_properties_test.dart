// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

void main() {
  group('FolderProperties', () {
    test('round-trips through YAML', () {
      final props = FolderProperties(
        title: 'Project X',
        created: DateTime.utc(2026, 5, 22, 9),
      );
      final parsed = FolderProperties.parse(props.toYaml());

      expect(parsed.title, 'Project X');
      expect(parsed.created, DateTime.utc(2026, 5, 22, 9));
    });

    test('round-trips an optional color', () {
      final props = FolderProperties(
        title: 'Project X',
        created: DateTime.utc(2026, 5, 22, 9),
        color: '#E57373',
      );
      final parsed = FolderProperties.parse(props.toYaml());
      expect(parsed.color, '#E57373');
    });

    test('omits color when absent', () {
      final props = FolderProperties(
        title: 'No color',
        created: DateTime.utc(2026, 5, 22, 9),
      );
      expect(props.toYaml().contains('color:'), isFalse);
      expect(FolderProperties.parse(props.toYaml()).color, isNull);
    });

    test('copyWith can clear the color', () {
      final props = FolderProperties(
        title: 'X',
        created: DateTime.utc(2026),
        color: '#FFB74D',
      );
      expect(props.copyWith(clearColor: true).color, isNull);
    });

    test('parse rejects a non-map document', () {
      expect(
        () => FolderProperties.parse('- just\n- a\n- list\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
