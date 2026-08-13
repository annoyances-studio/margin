// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/src/settings/recent_folios.dart';
import 'package:margin/src/storage/git/git_channel.dart';
import 'package:margin/src/ui/app_controller.dart';

/// A [GitChannel] that stands in for the native JGit bridge: it "clones" by
/// running [onClone], which returns the path of an already-prepared local
/// working tree (so the controller can browse it with a LocalFolderBackend).
class _FakeGit implements GitChannel {
  _FakeGit(this.onClone, {this.cachedPath});

  final Future<String> Function(String url) onClone;

  /// What [localPath] returns — a pre-existing clone on disk, or null.
  final String? cachedPath;

  int cloneCalls = 0;
  int pullCalls = 0;

  /// Runs on pull(); by default a no-op success. Set to throw to test failure.
  Future<void> Function()? onPull;

  @override
  Future<String> clone({
    required String url,
    String user = '',
    String password = '',
    required String name,
  }) {
    cloneCalls++;
    return onClone(url);
  }

  @override
  Future<String?> localPath(String name) async => cachedPath;

  @override
  Future<void> pull({
    required String path,
    required String url,
    String user = '',
    String password = '',
  }) async {
    pullCalls++;
    await onPull?.call();
  }
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
      // A git recent is recorded so reopening is one tap.
      expect(
        controller.recentFolios.any(
          (r) => r.type == 'git' && r.location == 'https://github.com/user/notes.git',
        ),
        isTrue,
      );
    });

    test('reopening a git recent uses the local cache, not a re-clone', () async {
      final dir = await Directory.systemTemp.createTemp('margin_git_cache');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/README.md').writeAsString('# Cached');

      final fake = _FakeGit(
        (_) => throw StateError('should not clone when cache exists'),
        cachedPath: dir.path,
      );
      final controller = AppController(git: fake);
      addTearDown(controller.dispose);

      await controller.openRecentFolio(const RecentFolio(
        type: 'git',
        location: 'https://github.com/user/notes.git',
        name: 'notes',
        browse: true,
      ));

      expect(controller.hasFolio, isTrue);
      expect(controller.isBrowsing, isTrue);
      expect(fake.cloneCalls, 0); // opened from cache, no network
    });

    test('refreshTree pulls the git clone, then reloads', () async {
      final dir = await Directory.systemTemp.createTemp('margin_git_pull');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/README.md').writeAsString('# n');

      final fake = _FakeGit((_) async => dir.path);
      final controller = AppController(git: fake);
      addTearDown(controller.dispose);
      await controller.browseGitRepo(
        url: 'https://github.com/user/notes.git',
        user: 'user',
        password: 'pat',
      );
      expect(controller.isGitFolio, isTrue);

      await controller.refreshTree();
      expect(fake.pullCalls, 1);
    });

    test('a failed pull keeps the folio open and warns (stale copy)', () async {
      final dir = await Directory.systemTemp.createTemp('margin_git_pullfail');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/README.md').writeAsString('# n');

      final fake = _FakeGit((_) async => dir.path)
        ..onPull = () => throw const GitException('network down');
      final controller = AppController(git: fake);
      addTearDown(controller.dispose);
      await controller.browseGitRepo(url: 'https://github.com/user/notes.git');

      await controller.refreshTree();

      expect(controller.hasFolio, isTrue); // last-good clone stays visible
      expect(controller.error, contains('last synced copy'));
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
