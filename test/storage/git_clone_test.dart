// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/storage/git/git_channel.dart';
import 'package:margin/src/ui/app_controller.dart';

/// A [GitChannel] that stands in for the native JGit bridge: it "clones" by
/// running [onClone], which returns the path of an already-prepared local
/// working tree (so the controller can browse it with a LocalFolderBackend).
class _FakeGit implements GitChannel {
  _FakeGit(this.onClone);

  final Future<String> Function(String url) onClone;

  @override
  Future<String> clone({
    required String url,
    String user = '',
    String password = '',
    required String name,
  }) =>
      onClone(url);
}

void main() {
  group('AppController.browseGitRepo', () {
    test('clones then browses the working tree read-only', () async {
      final dir = await Directory.systemTemp.createTemp('margin_git_test');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/README.md').writeAsString('# Cloned overview');

      final controller = AppController(
        git: _FakeGit((_) async => dir.path),
      );
      addTearDown(controller.dispose);

      await controller.browseGitRepo(
        url: 'https://github.com/user/notes.git',
        user: 'user',
        password: 'pat',
      );

      expect(controller.hasFolio, isTrue);
      expect(controller.isBrowsing, isTrue);
      // Display name is the last URL segment without the trailing `.git`.
      expect(controller.folioName, 'notes');
    });

    test('surfaces a clone failure as an error and opens nothing', () async {
      final controller = AppController(
        git: _FakeGit((_) => throw const GitException('auth failed')),
      );
      addTearDown(controller.dispose);

      await controller.browseGitRepo(url: 'https://github.com/user/notes.git');

      expect(controller.hasFolio, isFalse);
      expect(controller.error, contains('auth failed'));
    });
  });
}
