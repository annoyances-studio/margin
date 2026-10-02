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

/// macOS desktop specifically — the custom title bar keeps the native
/// traffic-lights there (left) and moves the Margin mark to the right.
bool get isMacOSDesktop => !kIsWeb && Platform.isMacOS;

/// Whether the window is currently maximized — so the custom title bar can show
/// the restore glyph instead of the maximize one. Kept current by [DesktopTray]
/// (a [WindowListener]); the UI watches it with a [ValueListenableBuilder].
final ValueNotifier<bool> windowMaximized = ValueNotifier<bool>(false);

/// Sets up the desktop window: a sensible size and "close hides to tray"
/// behaviour (DESIGN.md). No-op off desktop.
///
/// When [startMinimized] is true (a run-at-login launch with `--minimized`), the
/// window is prepared but not shown — the app lives in the tray until the user
/// opens it.
Future<void> initDesktopWindow({bool startMinimized = false}) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1100, 720),
    minimumSize: Size(640, 480),
    center: true,
    title: 'Margin•',
    // Hide the OS title bar — Margin draws its own merged bar. On macOS we keep
    // the native traffic-lights (windowButtonVisibility below); on Windows/Linux
    // the app draws its own window buttons.
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    try {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: Platform.isMacOS,
      );
    } catch (_) {}
    if (startMinimized) return; // stay hidden in the tray
    await windowManager.show();
    await windowManager.focus();
  });
  // Intercept the close button so it hides to the tray instead of quitting.
  await windowManager.setPreventClose(true);
}

/// Window-control actions for the custom title bar (desktop only; failures
/// swallowed so a missing window manager can't crash the UI).
Future<void> minimizeWindow() async {
  if (!isDesktop) return;
  try {
    await windowManager.minimize();
  } catch (_) {}
}

Future<void> toggleMaximizeWindow() async {
  if (!isDesktop) return;
  try {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  } catch (_) {}
}

/// Closes the window — which the tray guard turns into "hide to tray".
Future<void> closeWindow() async {
  if (!isDesktop) return;
  try {
    await windowManager.close();
  } catch (_) {}
}

/// Sets the OS window title (taskbar / alt-tab). Falls back to the app name.
Future<void> setWindowTitle(String title) async {
  if (!isDesktop) return;
  try {
    await windowManager.setTitle(title.trim().isEmpty ? 'Margin•' : title);
  } catch (_) {}
}

/// Quits the desktop app for real: drops the hide-to-tray guard and destroys
/// the window (the same path as the tray's "Quit"). No-op off desktop.
Future<void> quitDesktopApp() async {
  if (!isDesktop) return;
  await DesktopTray.instance._quit();
}

/// Sets whether the window floats above other windows. No-op off desktop;
/// failures are swallowed so a missing window manager can't crash the UI.
Future<void> setWindowAlwaysOnTop(bool value) async {
  if (!isDesktop) return;
  try {
    await windowManager.setAlwaysOnTop(value);
  } catch (e) {
    debugPrint('setAlwaysOnTop failed: $e');
  }
}

/// Installs the system tray icon and menu, and routes the window-close event to
/// "hide to tray". Quit is available from the tray menu. No-op off desktop.
class DesktopTray with TrayListener, WindowListener {
  DesktopTray._();

  static final DesktopTray instance = DesktopTray._();

  static const String _iconWindows = 'assets/tray_icon.ico';
  static const String _iconOther = 'assets/tray_icon.png';

  /// Invoked just before the window hides to the tray or the app quits, so the
  /// UI layer can flush unsaved work (the open note). Set by the app. Best
  /// effort; failures are swallowed so they can't block hiding/quitting.
  Future<void> Function()? beforeHide;

  Future<void> _runBeforeHide() async {
    try {
      await beforeHide?.call();
    } catch (e) {
      debugPrint('beforeHide failed: $e');
    }
  }

  Future<void> setup() async {
    if (!isDesktop) return;
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      windowMaximized.value = await windowManager.isMaximized();
    } catch (_) {}
    try {
      await trayManager.setIcon(Platform.isWindows ? _iconWindows : _iconOther);
      await trayManager.setToolTip('Margin•');
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
  void onWindowMaximize() => windowMaximized.value = true;

  @override
  void onWindowUnmaximize() => windowMaximized.value = false;

  @override
  void onWindowClose() async {
    // Hide instead of destroying so the app lives on in the tray — but flush
    // the open note first so closing to the tray never loses unsaved edits.
    if (await windowManager.isPreventClose()) {
      await _runBeforeHide();
      await windowManager.hide();
    }
  }

  Future<void> _quit() async {
    await _runBeforeHide(); // save the open note before tearing the app down
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
