#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <DbgHelp.h>
#include <shlobj.h>
#include <time.h>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

#pragma comment(lib, "DbgHelp.lib")

LONG WINAPI CreateCrashMinidump(EXCEPTION_POINTERS* pExceptionPointers) {
  if (::IsDebuggerPresent()) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  wchar_t appDataPath[MAX_PATH];
  if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_APPDATA, NULL, 0, appDataPath))) {
    std::wstring crashDir = std::wstring(appDataPath) + L"\\com.adbtoolkit.app\\adb_toolkit\\crashes";
    CreateDirectoryW(crashDir.c_str(), NULL);

    time_t rawtime;
    time(&rawtime);
    struct tm timeinfo;
    localtime_s(&timeinfo, &rawtime);
    wchar_t fileName[MAX_PATH];
    swprintf_s(fileName, MAX_PATH, L"%s\\crash_%04d%02d%02d_%02d%02d%02d.dmp",
              crashDir.c_str(),
              timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday,
              timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);

    HANDLE hFile = CreateFileW(fileName, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile != INVALID_HANDLE_VALUE) {
      MINIDUMP_EXCEPTION_INFORMATION mdei;
      mdei.ThreadId = GetCurrentThreadId();
      mdei.ExceptionPointers = pExceptionPointers;
      mdei.ClientPointers = FALSE;

      MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), hFile, MiniDumpNormal, &mdei, NULL, NULL);
      CloseHandle(hFile);
    }
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::SetUnhandledExceptionFilter(CreateCrashMinidump);
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
  if (!window.Create(L"ADB Toolkit", origin, size)) {
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
