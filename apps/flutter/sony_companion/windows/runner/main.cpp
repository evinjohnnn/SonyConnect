#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  // A tall 2:3 window, as on macOS (logical pixels; scaled for DPI), limited
  // to the monitor's work area so a 768 px-tall or 150%-scaled screen still
  // shows the whole window.
  int height = 900;
  const POINT origin_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = ::MonitorFromPoint(origin_point, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info = {sizeof(monitor_info)};
  if (::GetMonitorInfo(monitor, &monitor_info)) {
    const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
    const int work_height = static_cast<int>(
        (monitor_info.rcWork.bottom - monitor_info.rcWork.top) / scale);
    height = std::clamp(work_height - 2 * origin.y, 640, 900);
  }
  Win32Window::Size size(height * 2 / 3, height);
  if (!window.Create(L"sony_companion", origin, size)) {
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
