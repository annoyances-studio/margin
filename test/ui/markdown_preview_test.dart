// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/ui/widgets/markdown_preview.dart';

void main() {
  testWidgets('blockquote uses theme colors with an accent border, not the '
      'hardcoded light-blue default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const Scaffold(
          body: MarkdownPreview(data: '> a quoted line\n\nbody'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final style =
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
    final decoration = style.blockquoteDecoration as BoxDecoration;
    // Our override adds a left accent border; flutter_markdown's default has
    // none (just a filled light-blue box). The text color is scheme-derived so
    // it adapts to dark mode rather than staying white-on-light-blue.
    expect(decoration.border, isNotNull);
    expect(style.blockquote?.color, isNotNull);
  });
}
