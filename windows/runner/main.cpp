#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// SetCurrentProcessExplicitAppUserModelID lives in shell32.
#pragma comment(lib, "shell32.lib")

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance: a stable AppUserModelID groups the taskbar button (and a
  // pinned shortcut) under one identity, and a named mutex ensures a second
  // launch (e.g. clicking the pinned icon) surfaces the running window and
  // exits instead of opening a duplicate.
  ::SetCurrentProcessExplicitAppUserModelID(L"AnnoyancesStudio.Margin");
  ::CreateMutexW(nullptr, FALSE, L"studio.annoyances.margin.SingleInstance");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Grant the running instance permission to steal focus, then ask it to
    // surface. HWND_BROADCAST reaches its top-level window even when it is
    // hidden in the tray; only Margin's window proc handles this message.
    ::AllowSetForegroundWindow(ASFW_ANY);
    ::PostMessage(HWND_BROADCAST, GetMarginShowMessage(), 0, 0);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"margin", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
