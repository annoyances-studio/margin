// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/widgets/note_editor.dart';

import '../support/test_app.dart';

void main() {
  Future<TextEditingController> pumpEditor(
    WidgetTester tester, {
    required String body,
    String? imageBaseDir,
  }) async {
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: SizedBox(
            width: 420,
            height: 600,
            child: NoteEditor(
              notePath: 'Work/note.md',
              body: body,
              onChanged: (_) {},
              imageBaseDir: imageBaseDir,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<TextField>(find.byType(TextField)).controller!;
  }

  testWidgets('no affordance until the caret enters a link', (tester) async {
    final controller =
        await pumpEditor(tester, body: 'see [docs](https://example.com) end');

    expect(find.byKey(const Key('linkAffordance')), findsNothing);

    // 'see ' is 4 chars, so offset 6 lands inside [docs](...).
    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();

    expect(find.byKey(const Key('linkAffordance')), findsOneWidget);
    // The [label] is shown in preference to the target URL.
    expect(find.text('docs'), findsOneWidget);
  });

  testWidgets('falls back to the target when the link has no label',
      (tester) async {
    final controller =
        await pumpEditor(tester, body: 'bare [](https://example.com) end');

    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();

    expect(find.byKey(const Key('linkAffordance')), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
  });

  testWidgets('affordance disappears when the caret leaves the link',
      (tester) async {
    final controller =
        await pumpEditor(tester, body: 'see [docs](https://example.com) end');

    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    expect(find.byKey(const Key('linkAffordance')), findsOneWidget);

    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    expect(find.byKey(const Key('linkAffordance')), findsNothing);
  });

  testWidgets('image link shows the affordance with its target', (tester) async {
    final controller = await pumpEditor(
      tester,
      body: 'pic ![alt](images/a.png) here',
      imageBaseDir: '/repo/Work',
    );

    // Caret inside the image token.
    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();

    expect(find.byKey(const Key('linkAffordance')), findsOneWidget);
    // The image's alt text (its [label]) is shown.
    expect(find.text('alt'), findsOneWidget);
    // The image file doesn't exist in tests; drain the handled load error so
    // it doesn't fail teardown.
    tester.takeException();
  });

  testWidgets('a non-ASCII image name builds the affordance without throwing',
      (tester) async {
    final controller = await pumpEditor(
      tester,
      // A long, non-ASCII name — the case that used to throw in resolution and
      // grey out the editor.
      body: 'x ![長い名前のファイル](images/長い名前のファイル.png) y',
      imageBaseDir: '/repo/Work',
    );

    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();

    // Builds fine (no synchronous throw) and shows the label.
    expect(find.byKey(const Key('linkAffordance')), findsOneWidget);
    expect(find.text('長い名前のファイル'), findsOneWidget);
    // The image file doesn't exist in tests; drain the handled load error.
    tester.takeException();
  });
}
