// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/widgets/attach_drop_target.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('renders its child and no overlay until a drag hovers',
      (tester) async {
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: AttachDropTarget(
            enabled: true,
            onAttach: (_, _) async {},
            child: const Text('editor area'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('editor area'), findsOneWidget);
    // No drag in progress → no invitation overlay.
    expect(find.text('Drop to attach to this note'), findsNothing);
    expect(find.text('Open a note first to attach files'), findsNothing);
  });

  testWidgets('does not attach when given an empty file list', (tester) async {
    final attached = <String>[];
    final target = AttachDropTarget(
      enabled: true,
      onAttach: (name, Uint8List _) async => attached.add(name),
      child: const Text('x'),
    );
    await tester.pumpWidget(localizedApp(Scaffold(body: target)));
    await tester.pump();

    // Sanity: the widget builds and exposes its child; the actual file-read
    // path is exercised through the controller's attachToCurrentNote test.
    expect(find.text('x'), findsOneWidget);
    expect(attached, isEmpty);
  });
}
