// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'open_repository_screen.dart';
import 'repository_screen.dart';

/// Root widget: themes the app and shows either the open/create screen or the
/// repository screen depending on whether a repository is open.
class MarginApp extends StatefulWidget {
  const MarginApp({super.key});

  @override
  State<MarginApp> createState() => _MarginAppState();
}

class _MarginAppState extends State<MarginApp> {
  final AppController _controller = AppController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Margin',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return _controller.hasRepository
              ? RepositoryScreen(controller: _controller)
              : OpenRepositoryScreen(controller: _controller);
        },
      ),
    );
  }
}
