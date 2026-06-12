// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Whether [error] is the kind of failure a brief network blip produces —
/// worth retrying silently — as opposed to a real problem (auth, bad request,
/// invalid data) that should surface immediately.
///
/// Mobile radios hand off between cellular and WiFi all the time, cutting any
/// in-flight request ("Software caused connection abort"). Those arrive as
/// transport-layer exceptions; protocol-level failures (HTTP 4xx/5xx) are
/// reported by the backends as their own exception types and are NOT matched
/// here.
bool isTransientNetworkError(Object error) =>
    error is SocketException || // connection reset/abort/refused, no route
    error is http.ClientException || // package:http transport failure
    error is TimeoutException ||
    error is TlsException || // TLS/handshake cut mid-negotiation
    error is HttpException; // dart:io "connection closed before ..." class
