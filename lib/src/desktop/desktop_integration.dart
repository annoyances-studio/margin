// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// True on desktop platforms, where window management and a tray icon apply.
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Sets up the desktop window: a sensible size and "close hides to tray"
/// behaviour (DESIGN.md). No-op off desktop.
Future<void> initDesktopWindow() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1100, 720),
    minimumSize: Size(640, 480),
    center: true,
    title: 'Margin',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // Intercept the close button so it hides to the tray instead of quitting.
  await windowManager.setPreventClose(true);
}

/// Installs the system tray icon and menu, and routes the window-close event to
/// "hide to tray". Quit is available from the tray menu. No-op off desktop.
class DesktopTray with TrayListener, WindowListener {
  DesktopTray._();

  static final DesktopTray instance = DesktopTray._();

  static const String _iconWindows = 'assets/tray_icon.ico';
  static const String _iconOther = 'assets/tray_icon.png';

  Future<void> setup() async {
    if (!isDesktop) return;
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      await trayManager.setIcon(Platform.isWindows ? _iconWindows : _iconOther);
      await trayManager.setToolTip('Margin');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Show Margin'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit'),
      ]));
    } catch (e) {
      // A missing tray (or icon) must not stop the app from running.
      debugPrint('Tray setup failed: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
      case 'quit':
        _quit();
    }
  }

  @override
  void onWindowClose() async {
    // Hide instead of destroying so the app lives on in the tray.
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
