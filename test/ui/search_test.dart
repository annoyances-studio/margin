// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';

void main() {
  Future<AppController> folioWithNotes() async {
    final c = AppController();
    addTearDown(c.dispose);
    final backend = MemoryBackend();
    await c.create(backend, 'Notes');
    await c.createFolder('Work');
    await c.createFolder('Personal');
    // A note whose frontmatter title + tags differ from the file name.
    await c.createNote('q2-plan', folderPath: 'Work');
    await c.save();
    // Give it a frontmatter title and tags via a direct save.
    final content = ContentService(backend);
    await content.saveNote(
      'Work/q2-plan.md',
      Note(
        frontmatter: const NoteFrontmatter(
          title: 'Quarterly roadmap',
          tags: ['planning', 'urgent'],
        ),
        body: 'body',
      ),
    );
    await c.createNote('groceries', folderPath: 'Personal');
    // Rebuild the controller's tree/index to reflect the direct save.
    await c.open(backend);
    return c;
  }

  test('matches the file-name title', () async {
    final c = await folioWithNotes();
    await c.setSearchQuery('groc');
    expect(c.searchResults.map((n) => n.name), ['groceries.md']);
  });

  test('matches the frontmatter title from the sidecar', () async {
    final c = await folioWithNotes();
    await c.setSearchQuery('roadmap');
    expect(c.searchResults.map((n) => n.name), ['q2-plan.md']);
  });

  test('matches a tag from the sidecar', () async {
    final c = await folioWithNotes();
    await c.setSearchQuery('urgent');
    expect(c.searchResults.map((n) => n.name), ['q2-plan.md']);
  });

  test('is case-insensitive and clears', () async {
    final c = await folioWithNotes();
    await c.setSearchQuery('PLANNING');
    expect(c.isSearching, isTrue);
    expect(c.searchResults, isNotEmpty);

    c.clearSearch();
    expect(c.isSearching, isFalse);
    expect(c.searchResults, isEmpty);
  });

  test('an unmatched query yields no results', () async {
    final c = await folioWithNotes();
    await c.setSearchQuery('zzz-nothing');
    expect(c.searchResults, isEmpty);
  });
}
