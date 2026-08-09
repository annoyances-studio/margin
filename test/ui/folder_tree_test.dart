// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/widgets/folder_tree.dart';

import '../support/test_app.dart';

void main() {
  FolderNode treeWith(NoteNode n1, NoteNode n2) => FolderNode(
        path: '',
        name: '',
        folders: [
          FolderNode(
            path: 'A',
            name: 'A',
            notes: [n1],
            folders: [
              FolderNode(path: 'A/B', name: 'B', notes: [n2]),
            ],
          ),
        ],
      );

  Widget host(FolderNode root) => localizedApp(Scaffold(
        body: FolderTreeView(
          root: root,
          onNoteTap: (_) {},
          onFolderAction: (_, _) {},
          onNoteAction: (_, _) {},
          onOpenFolderNote: (_) {},
        ),
      ));

  testWidgets('collapse all hides a subtree; expand all restores it',
      (tester) async {
    await tester.pumpWidget(host(treeWith(
      const NoteNode(path: 'A/n1.md', name: 'n1.md'),
      const NoteNode(path: 'A/B/n2.md', name: 'n2.md'),
    )));
    await tester.pumpAndSettle();

    // Both notes visible initially (folders default expanded).
    expect(find.text('n1'), findsOneWidget);
    expect(find.text('n2'), findsOneWidget);

    // Folder A's menu → Collapse all.
    await tester.tap(find.byType(PopupMenuButton<TreeAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.text('n1'), findsNothing);
    expect(find.text('n2'), findsNothing);

    // Folder A's menu → Expand all restores the whole subtree.
    await tester.tap(find.byType(PopupMenuButton<TreeAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();
    expect(find.text('n1'), findsOneWidget);
    expect(find.text('n2'), findsOneWidget);
  });

  testWidgets('a note carries a Modified/size tooltip from listing metadata',
      (tester) async {
    await tester.pumpWidget(host(treeWith(
      NoteNode(
        path: 'A/n1.md',
        name: 'n1.md',
        modified: DateTime(2026, 7, 16, 15, 24),
        size: 2048,
      ),
      const NoteNode(path: 'A/B/n2.md', name: 'n2.md'),
    )));
    await tester.pumpAndSettle();

    final tips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .where((t) => (t.message ?? '').contains('2.0 KB'));
    expect(tips, isNotEmpty);
    expect(tips.first.message, contains('Modified'));
  });

  testWidgets('the folder-note tooltip includes modified date and size',
      (tester) async {
    final root = FolderNode(path: '', name: '', folders: [
      FolderNode(
        path: 'A',
        name: 'A',
        hasFolderNote: true,
        folderNoteModified: DateTime(2026, 7, 16, 9, 5),
        folderNoteSize: 3072,
        notes: const [NoteNode(path: 'A/n.md', name: 'n.md')],
      ),
    ]);
    await tester.pumpWidget(host(root));
    await tester.pumpAndSettle();

    final tip = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .firstWhere((t) => (t.message ?? '').contains('README.md'));
    expect(tip.message, contains('Modified'));
    expect(tip.message, contains('3.0 KB'));
  });
}
