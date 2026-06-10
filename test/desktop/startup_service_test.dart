// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/desktop/startup_service.dart';

void main() {
  group('shouldStartMinimized', () {
    test('true when the run-at-login flag is present', () {
      expect(shouldStartMinimized(const [kStartMinimizedArg]), isTrue);
    });

    test('true when the flag is among other launch args', () {
      expect(
        shouldStartMinimized(const ['--foo', kStartMinimizedArg, '--bar']),
        isTrue,
      );
    });

    test('false for an empty arg list (a normal manual launch)', () {
      expect(shouldStartMinimized(const []), isFalse);
    });

    test('false when the flag is absent', () {
      expect(shouldStartMinimized(const ['--other']), isFalse);
    });
  });

  group('NoopStartupService', () {
    test('is unsupported and never enabled', () async {
      const service = NoopStartupService();
      expect(service.isSupported, isFalse);
      expect(await service.isEnabled(), isFalse);
      // Should be a no-op, not throw.
      await service.setEnabled(true, minimized: true);
      expect(await service.isEnabled(), isFalse);
    });
  });
}
