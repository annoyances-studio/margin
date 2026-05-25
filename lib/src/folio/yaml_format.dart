// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Minimal, safe YAML emission helpers for Margin's small, fixed schemas.
///
/// We deliberately avoid a general-purpose YAML writer: our documents are
/// simple (scalars, a list of strings, a list of flat maps). Strings are always
/// emitted as double-quoted scalars with escaping, which is valid YAML for any
/// value. Correctness is verified by round-trip tests that parse the output
/// back with package:yaml.
library;

/// Quotes [value] as a YAML double-quoted scalar, escaping characters that
/// would otherwise break the scalar.
String yamlQuote(String value) {
  final escaped = value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

/// Formats a [DateTime] as an ISO-8601 UTC string, quoted for YAML so it is
/// always read back as a string (which we then parse with [DateTime.parse]).
String yamlDate(DateTime value) => yamlQuote(value.toUtc().toIso8601String());
