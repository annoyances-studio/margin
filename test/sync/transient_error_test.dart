// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:margin/src/storage/storage_exception.dart';
import 'package:margin/src/sync/transient_error.dart';

void main() {
  test('network blips are transient', () {
    // The one seen in the wild: a WiFi handoff cutting a Graph request.
    expect(
      isTransientNetworkError(
          http.ClientException('Software caused connection abort')),
      isTrue,
    );
    expect(
      isTransientNetworkError(const SocketException('connection reset')),
      isTrue,
    );
    expect(isTransientNetworkError(TimeoutException('timed out')), isTrue);
    expect(
      isTransientNetworkError(const HandshakeException('TLS cut')),
      isTrue,
    );
    expect(
      isTransientNetworkError(
          const HttpException('Connection closed before full header')),
      isTrue,
    );
  });

  test('real problems are not transient', () {
    expect(isTransientNetworkError(const StorageException('HTTP 401')), isFalse);
    expect(isTransientNetworkError(const FormatException('bad yaml')), isFalse);
    expect(isTransientNetworkError(ArgumentError('nope')), isFalse);
    expect(isTransientNetworkError(StateError('nope')), isFalse);
  });
}
