// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
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

  testWidgets('preview links render natively and open via their recognizer',
      (tester) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownPreview(
            data: 'see [the guide](guides/intro.md) here',
            onOpenLink: (href) => opened = href,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The link is a native flutter_markdown span carrying a tap recognizer —
    // not a per-link widget (which broke the link-handler stack and made
    // following text clickable). No Tooltip either.
    TapGestureRecognizer? recognizer;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((s) {
        if (s is TextSpan &&
            s.text == 'the guide' &&
            s.recognizer is TapGestureRecognizer) {
          recognizer = s.recognizer as TapGestureRecognizer;
          return false;
        }
        return true;
      });
      if (recognizer != null) break;
    }
    expect(recognizer, isNotNull, reason: 'link is a native tap span');
    expect(find.byType(Tooltip), findsNothing);

    // The surrounding text ("see ", " here") carries no recognizer, so tapping
    // plain text never navigates.
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((s) {
        if (s is TextSpan && (s.text == 'see ' || s.text == ' here')) {
          expect(s.recognizer, isNull);
        }
        return true;
      });
    }

    // Invoking the link's recognizer opens it.
    recognizer!.onTap!();
    expect(opened, 'guides/intro.md');
  });
}
