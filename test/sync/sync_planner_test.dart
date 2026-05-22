// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/margin.dart';

void main() {
  // The planner treats hashes as opaque strings, so fakes are fine here.
  SyncPlan planOne({
    String? local,
    String? remote,
    String? base,
    String path = 'Work/note.md',
  }) {
    return SyncPlanner.plan(
      local: {path: ?local},
      remote: {path: ?remote},
      base: {path: ?base},
      conflictLabel: 'Phone, 2026-05-22',
    );
  }

  SyncAction? only(SyncPlan plan) =>
      plan.actions.isEmpty ? null : plan.actions.single;

  group('SyncPlanner — single path', () {
    test('unchanged on both sides: no action', () {
      final plan = planOne(local: 'h1', remote: 'h1', base: 'h1');
      expect(plan.actions, isEmpty);
      expect(plan.resultingState['Work/note.md'], 'h1');
    });

    test('new local file: push to remote', () {
      final plan = planOne(local: 'h1');
      expect(only(plan)?.type, SyncActionType.pushToRemote);
      expect(plan.resultingState['Work/note.md'], 'h1');
    });

    test('new remote file: pull to local', () {
      final plan = planOne(remote: 'h1');
      expect(only(plan)?.type, SyncActionType.pullToLocal);
      expect(plan.resultingState['Work/note.md'], 'h1');
    });

    test('local modified: push', () {
      final plan = planOne(local: 'h2', remote: 'h1', base: 'h1');
      expect(only(plan)?.type, SyncActionType.pushToRemote);
      expect(plan.resultingState['Work/note.md'], 'h2');
    });

    test('remote modified: pull', () {
      final plan = planOne(local: 'h1', remote: 'h2', base: 'h1');
      expect(only(plan)?.type, SyncActionType.pullToLocal);
      expect(plan.resultingState['Work/note.md'], 'h2');
    });

    test('local deleted: delete remote', () {
      final plan = planOne(remote: 'h1', base: 'h1');
      expect(only(plan)?.type, SyncActionType.deleteRemote);
      expect(plan.resultingState.containsKey('Work/note.md'), isFalse);
    });

    test('remote deleted: delete local', () {
      final plan = planOne(local: 'h1', base: 'h1');
      expect(only(plan)?.type, SyncActionType.deleteLocal);
      expect(plan.resultingState.containsKey('Work/note.md'), isFalse);
    });

    test('both made the same edit: no action', () {
      final plan = planOne(local: 'h2', remote: 'h2', base: 'h1');
      expect(plan.actions, isEmpty);
      expect(plan.resultingState['Work/note.md'], 'h2');
    });

    test('both deleted: no action', () {
      final plan = planOne(base: 'h1');
      expect(plan.actions, isEmpty);
      expect(plan.resultingState.containsKey('Work/note.md'), isFalse);
    });

    test('both modified differently: conflict copy', () {
      final plan = planOne(local: 'hLocal', remote: 'hRemote', base: 'h1');
      final action = only(plan)!;
      expect(action.type, SyncActionType.conflict);
      expect(action.conflictCopyPath,
          'Work/note (conflict, Phone, 2026-05-22).md');
      // Original converges to remote; local version preserved as the copy.
      expect(plan.resultingState['Work/note.md'], 'hRemote');
      expect(plan.resultingState[action.conflictCopyPath], 'hLocal');
      expect(plan.conflicts, hasLength(1));
    });

    test('both created different content: conflict', () {
      final plan = planOne(local: 'hLocal', remote: 'hRemote');
      expect(only(plan)?.type, SyncActionType.conflict);
    });

    test('deleted locally but edited remotely: keep the edit (pull)', () {
      final plan = planOne(remote: 'h2', base: 'h1');
      expect(only(plan)?.type, SyncActionType.pullToLocal);
      expect(plan.resultingState['Work/note.md'], 'h2');
    });

    test('edited locally but deleted remotely: keep the edit (push)', () {
      final plan = planOne(local: 'h2', base: 'h1');
      expect(only(plan)?.type, SyncActionType.pushToRemote);
      expect(plan.resultingState['Work/note.md'], 'h2');
    });
  });

  group('conflictCopyName', () {
    test('inserts before the extension, preserving the folder', () {
      expect(
        SyncPlanner.conflictCopyName('Work/note.md', 'Phone, 2026-05-22'),
        'Work/note (conflict, Phone, 2026-05-22).md',
      );
    });

    test('works at the root with no folder', () {
      expect(
        SyncPlanner.conflictCopyName('note.md', 'Desktop, 2026-01-01'),
        'note (conflict, Desktop, 2026-01-01).md',
      );
    });
  });

  group('SyncPlanner — multiple paths', () {
    test('mixes push, pull and conflict across files', () {
      final plan = SyncPlanner.plan(
        local: {'a.md': 'A1', 'b.md': 'B0', 'c.md': 'cLocal'},
        remote: {'b.md': 'B1', 'c.md': 'cRemote'},
        base: {'b.md': 'B0', 'c.md': 'c0'},
        conflictLabel: 'X, 2026-05-22',
      );

      final byPath = {for (final a in plan.actions) a.path: a.type};
      expect(byPath['a.md'], SyncActionType.pushToRemote); // new local
      expect(byPath['b.md'], SyncActionType.pullToLocal); // remote edited
      expect(byPath['c.md'], SyncActionType.conflict); // both edited
    });
  });
}
