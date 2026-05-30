// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';
import 'package:margin/src/ui/margin_app.dart';

void main() {
  // Dispatches an app lifecycle transition the way the engine does.
  Future<void> sendLifecycle(WidgetTester tester, String state) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage('AppLifecycleState.$state'),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets('losing the foreground saves the open note', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await controller.create(MemoryBackend(), 'Notes');
    await controller.createFolder('Work');
    await controller.createNote('n', folderPath: 'Work');

    controller.updateBody('# edited but not explicitly saved');
    expect(controller.isDirty, isTrue);

    await tester.pumpWidget(MarginApp(controller: controller));
    await tester.pumpAndSettle();

    // Backgrounding (app switch / minimize / close-to-tray) flushes the buffer.
    await sendLifecycle(tester, 'paused');

    expect(controller.isDirty, isFalse);
    // The flushed note now carries the edited body.
    expect(controller.currentNote!.body, contains('edited but not explicitly saved'));
  });

  testWidgets('a clean buffer is untouched on background', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await controller.create(MemoryBackend(), 'Notes');
    await controller.createFolder('Work');
    await controller.createNote('n', folderPath: 'Work');
    expect(controller.isDirty, isFalse);

    await tester.pumpWidget(MarginApp(controller: controller));
    await tester.pumpAndSettle();

    await sendLifecycle(tester, 'inactive'); // must not throw / no-op
    expect(controller.isDirty, isFalse);
  });
}
