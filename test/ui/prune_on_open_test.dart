// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';
import 'package:margin/src/ui/app_controller.dart';

void main() {
  test('opening a local Folio prunes leftover empty folders', () async {
    final tmp = await Directory.systemTemp.createTemp('margin_prune_open_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final backend = LocalFolderBackend(tmp.path);

    final setup = AppController();
    await setup.create(backend, 'Notes');
    await setup.createFolder('Keep'); // marked folder (has properties.yaml)
    setup.dispose();

    // Simulate an out-of-app deletion that left an empty directory behind
    // (the OneDrive/Dropbox "deleted the files, kept the folder" case).
    await backend.write('Leftover/note.md', Uint8List.fromList([1, 2, 3]));
    await backend.delete('Leftover/note.md');
    expect(await backend.exists('Leftover'), isTrue); // empty dir remains

    final c = AppController();
    addTearDown(c.dispose);
    await c.open(backend); // re-open should prune the leftover

    expect(await backend.exists('Leftover'), isFalse); // pruned
    expect(await backend.exists('Keep/properties.yaml'), isTrue); // kept
  });
}
