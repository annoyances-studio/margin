// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:margin/src/storage/onedrive_backend.dart';
import 'package:margin/src/storage/storage_exception.dart';

OneDriveBackend backendWith(
  MockClientHandler handler, {
  String rootPath = 'Apps/Margin',
}) =>
    OneDriveBackend(
      rootPath: rootPath,
      accessToken: () async => 'fake-token',
      client: MockClient(handler),
    );

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('read returns file content via the content endpoint', () async {
    late Uri seenUrl;
    final backend = backendWith((req) async {
      seenUrl = req.url;
      expect(req.headers['authorization'], 'Bearer fake-token');
      return http.Response('file body', 200);
    });

    final data = await backend.read('Work/note.md');
    expect(utf8.decode(data), 'file body');
    expect(
      seenUrl.toString(),
      'https://graph.microsoft.com/v1.0/me/drive/root:/Apps/Margin/Work/note.md:/content',
    );
  });

  test('read maps a 404 to NotFoundException', () async {
    final backend = backendWith((_) async => http.Response('', 404));
    expect(backend.read('missing.md'), throwsA(isA<NotFoundException>()));
  });

  test('exists is true for 200, false for 404, and true at the root', () async {
    // Everything resolves except an explicit "gone.md" lookup. The root item
    // lookup (Apps/Margin) therefore answers 200, so exists('') is true.
    final backend = backendWith((req) async =>
        req.url.path.endsWith('/gone.md') ? http.Response('', 404) : http.Response('', 200));

    expect(await backend.exists('here.md'), isTrue);
    expect(await backend.exists('gone.md'), isFalse);
    expect(await backend.exists(''), isTrue); // Folio root folder exists
  });

  test('list parses children (file vs folder, size, modified)', () async {
    final backend = backendWith((req) async {
      expect(
        req.url.toString(),
        'https://graph.microsoft.com/v1.0/me/drive/root:/Apps/Margin/Work:/children',
      );
      return http.Response(
        jsonEncode({
          'value': [
            {
              'name': 'sub',
              'folder': {'childCount': 0},
            },
            {
              'name': 'note.md',
              'file': {'mimeType': 'text/markdown'},
              'size': 12,
              'lastModifiedDateTime': '2026-05-01T10:00:00Z',
            },
          ],
        }),
        200,
      );
    });

    final entries = await backend.list('Work');
    expect(entries.length, 2);
    final dir = entries.firstWhere((e) => e.isDirectory);
    final file = entries.firstWhere((e) => !e.isDirectory);
    expect(dir.path, 'Work/sub');
    expect(file.path, 'Work/note.md');
    expect(file.size, 12);
    expect(file.modified, DateTime.utc(2026, 5, 1, 10));
  });

  test('list follows @odata.nextLink (pagination)', () async {
    var page = 0;
    final backend = backendWith((req) async {
      page++;
      if (req.url.toString().contains('skiptoken')) {
        return http.Response(
          jsonEncode({
            'value': [
              {'name': 'b.md', 'file': {}, 'size': 1},
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'value': [
            {'name': 'a.md', 'file': {}, 'size': 1},
          ],
          '@odata.nextLink':
              'https://graph.microsoft.com/v1.0/me/drive/root/children?skiptoken=XYZ',
        }),
        200,
      );
    });

    final entries = await backend.list('');
    expect(page, 2); // two pages fetched
    expect(entries.map((e) => e.path), containsAll(['a.md', 'b.md']));
  });

  test('list maps a 404 to NotFoundException', () async {
    final backend = backendWith((_) async => http.Response('', 404));
    expect(backend.list('nope'), throwsA(isA<NotFoundException>()));
  });

  test('write creates missing folders below the root, then uploads', () async {
    final created = <String>[];
    String? putUrl;
    final backend = backendWith((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/children')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        created.add(body['name'] as String);
        return http.Response('', 201);
      }
      if (req.method == 'PUT') {
        putUrl = req.url.toString();
        return http.Response('', 201);
      }
      return http.Response('unexpected', 400);
    });

    await backend.write('Work/note.md', bytes('hi'));

    // Only the folder below the root ("Work") is created — not Apps/Margin.
    expect(created, ['Work']);
    expect(
      putUrl,
      'https://graph.microsoft.com/v1.0/me/drive/root:/Apps/Margin/Work/note.md:/content',
    );
  });

  test('write treats a 409 on folder create as already-exists', () async {
    final backend = backendWith((req) async {
      if (req.method == 'POST') return http.Response('exists', 409);
      if (req.method == 'PUT') return http.Response('', 201);
      return http.Response('', 400);
    });
    await backend.write('Work/note.md', bytes('hi')); // must not throw
  });

  test('write rejects the Folio root', () async {
    final backend = backendWith((_) async => http.Response('', 200));
    expect(backend.write('', bytes('x')), throwsA(isA<InvalidPathException>()));
  });

  test('delete succeeds on 204 and is a no-op on 404', () async {
    var status = 204;
    final backend = backendWith((req) async {
      expect(req.method, 'DELETE');
      return http.Response('', status);
    });

    await backend.delete('Work/note.md'); // 204
    status = 404;
    await backend.delete('Work/gone.md'); // 404 = no-op, must not throw
  });

  test('rejects paths containing ".."', () async {
    final backend = backendWith((_) async => http.Response('', 200));
    expect(backend.read('../escape.md'), throwsA(isA<InvalidPathException>()));
  });

  test('URL-encodes non-ASCII names (e.g. Japanese)', () async {
    late Uri seenUrl;
    final backend = backendWith((req) async {
      seenUrl = req.url;
      return http.Response('x', 200);
    });

    await backend.read('メモ.md');
    // The segment is percent-encoded; the path separators are not.
    expect(seenUrl.toString(), contains('/Apps/Margin/'));
    expect(seenUrl.toString(), contains('%E3%83%A1%E3%83%A2.md'));
  });

  test('retries on 429 honoring Retry-After, then succeeds', () async {
    var calls = 0;
    final backend = backendWith((req) async {
      calls++;
      if (calls == 1) {
        return http.Response('throttled', 429, headers: {'retry-after': '0'});
      }
      return http.Response('ok', 200);
    });

    final data = await backend.read('Work/note.md');
    expect(utf8.decode(data), 'ok');
    expect(calls, 2); // one throttle, one success
  });

  test('ensureRoot creates the whole root folder chain', () async {
    final created = <String>[];
    final backend = backendWith(
      rootPath: 'Apps/Margin/Notes',
      (req) async {
        if (req.method == 'POST') {
          created.add((jsonDecode(req.body) as Map<String, dynamic>)['name'] as String);
          return http.Response('', 201);
        }
        return http.Response('', 400);
      },
    );

    await backend.ensureRoot();
    expect(created, ['Apps', 'Margin', 'Notes']);
  });

  test('works at the drive root when rootPath is empty', () async {
    late Uri listUrl;
    final backend = backendWith(
      rootPath: '',
      (req) async {
        listUrl = req.url;
        return http.Response(jsonEncode({'value': []}), 200);
      },
    );

    await backend.list('');
    expect(listUrl.toString(),
        'https://graph.microsoft.com/v1.0/me/drive/root/children');
  });
}
