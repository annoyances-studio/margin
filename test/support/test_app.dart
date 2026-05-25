// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:margin/l10n/app_localizations.dart';

/// Wraps [home] in a [MaterialApp] with the app's localization delegates, so
/// widgets that call `AppLocalizations.of(context)` work under test. Defaults
/// to the English locale.
Widget localizedApp(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
