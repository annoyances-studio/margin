// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:margin/margin.dart';

void main() {
  final base = Uri.parse('https://dav.example.com/dav/Notes/');

  /// Builds a backend whose HTTP is served by [handler], recording every
  /// request into [log] for assertions.
  WebDavBackend backendWith(
    List<http.Request> log,
    Future<http.Response> Function(http.Request) handler, {
    String? username,
    String? password,
  }) {
    return WebDavBackend(
      baseUrl: base,
      username: username,
      password: password,
      client: MockClient((request) {
        log.add(request);
        return handler(request);
      }),
    );
  }

  group('read', () {
    test('GET 200 returns the bytes', () async {
      final log = <http.Request>[];
      final backend = backendWith(log, (req) async {
        expect(req.method, 'GET');
        return http.Response('hello', 200);
      });

      final bytes = await backend.read('Work/note.md');
      expect(utf8.decode(bytes), 'hello');
      expect(log.single.url.pathSegments, ['dav', 'Notes', 'Work', 'note.md']);
    });

    test('GET 404 throws NotFoundException', () async {
      final backend = backendWith([], (_) async => http.Response('', 404));
      expect(() => backend.read('missing.md'),
          throwsA(isA<NotFoundException>()));
    });
  });

  group('write', () {
    test('creates parent collections then PUTs the file', () async {
      final log = <http.Request>[];
      final backend = backendWith(log, (req) async {
        if (req.method == 'MKCOL') return http.Response('', 201);
        return http.Response('', 201); // PUT created
      });

      await backend.write('a/b/note.md', Uint8List.fromList([1, 2, 3]));

      final methods = log.map((r) => '${r.method} ${r.url.path}').toList();
      // Parent collections a/ and a/b/ are created before the PUT.
      expect(methods, [
        'MKCOL /dav/Notes/a/',
        'MKCOL /dav/Notes/a/b/',
        'PUT /dav/Notes/a/b/note.md',
      ]);
    });

    test('rejects writing the root', () {
      final backend = backendWith([], (_) async => http.Response('', 200));
      expect(() => backend.write('', Uint8List(0)),
          throwsA(isA<InvalidPathException>()));
    });
  });

  group('delete', () {
    test('404 is a no-op (no throw)', () async {
      final backend = backendWith([], (_) async => http.Response('', 404));
      await backend.delete('gone.md'); // must not throw
    });

    test('2xx succeeds', () async {
      final backend = backendWith([], (_) async => http.Response('', 204));
      await backend.delete('note.md');
    });
  });

  group('exists', () {
    test('PROPFIND 207 is true, 404 is false', () async {
      final present =
          backendWith([], (_) async => http.Response('<multistatus/>', 207));
      final absent = backendWith([], (_) async => http.Response('', 404));
      expect(await present.exists('note.md'), isTrue);
      expect(await absent.exists('note.md'), isFalse);
    });
  });

  group('list', () {
    const body = '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/Notes/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Notes/Work/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Notes/properties.yaml</D:href>
    <D:propstat><D:prop>
      <D:resourcetype/>
      <D:getcontentlength>123</D:getcontentlength>
      <D:getlastmodified>Mon, 12 Jan 2026 10:00:00 GMT</D:getlastmodified>
    </D:prop></D:propstat>
  </D:response>
</D:multistatus>''';

    test('parses children, skipping the collection itself', () async {
      final log = <http.Request>[];
      final backend = backendWith(log, (req) async {
        expect(req.method, 'PROPFIND');
        expect(req.headers['depth'], '1');
        return http.Response(body, 207);
      });

      final entries = await backend.list('');
      expect(entries.length, 2);

      final work = entries.firstWhere((e) => e.path == 'Work');
      expect(work.isDirectory, isTrue);

      final props = entries.firstWhere((e) => e.path == 'properties.yaml');
      expect(props.isDirectory, isFalse);
      expect(props.size, 123);
      expect(props.modified, DateTime.utc(2026, 1, 12, 10));
    });

    test('PROPFIND 404 throws NotFoundException', () async {
      final backend = backendWith([], (_) async => http.Response('', 404));
      expect(() => backend.list('Missing'),
          throwsA(isA<NotFoundException>()));
    });
  });

  group('paths and auth', () {
    test('encodes spaces and Unicode in the URL', () async {
      final log = <http.Request>[];
      final backend = backendWith(log, (_) async => http.Response('x', 200));
      await backend.read('Work/長い 名前.md');
      // Segments round-trip decoded; the wire form is percent-encoded.
      expect(log.single.url.pathSegments.last, '長い 名前.md');
      expect(log.single.url.toString(), contains('%20'));
    });

    test('rejects ".." segments', () {
      final backend = backendWith([], (_) async => http.Response('', 200));
      expect(() => backend.read('../secret'),
          throwsA(isA<InvalidPathException>()));
    });

    test('sends Basic auth when credentials are given', () async {
      final log = <http.Request>[];
      final backend = backendWith(
        log,
        (_) async => http.Response('x', 200),
        username: 'me',
        password: 'pw',
      );
      await backend.read('note.md');
      final expected = 'Basic ${base64.encode(utf8.encode('me:pw'))}';
      expect(log.single.headers['authorization'], expected);
    });
  });
}
