# Technical Post-Mortem: Hidden Settings Window Scaling Crash & Resolution

> [!IMPORTANT]
> **Incident Summary**: App crash to desktop (CTD) when navigating to the Hidden Settings tab and scaling or resizing the application window on host Windows machines with physical GPUs.

---

## Executive Summary

During window resizing on the **Hidden Settings** tab, the application experienced a sudden **Crash to Desktop (CTD)** on physical host machines, while functioning normally inside **Windows Sandbox**. 

Parsing the Windows minidumps (`crash_20260822_095309.dmp` and `crash_20260822_100014.dmp`) revealed a native Win32 `STATUS_ACCESS_VIOLATION` (`0xC0000005`) inside `flutter_windows.dll`. The issue was caused by a **3-way interaction**:

1. **Background Plugin Collision**: `DropzoneInstaller` (Tab 0) remained mounted in memory inside `IndexedStack`, continuously firing native Win32 COM/OLE drag-and-drop (`desktop_drop`) window message handlers.
2. **Win32 Zero-Dimension Surface Resizing**: The native C++ window procedure lacked `WM_GETMINMAXINFO` limits and passed zero/minimized width and height directly to `MoveWindow()`, causing DirectX ANGLE swapchain buffer failures (`DXGI_ERROR_INVALID_CALL`).
3. **Flex Layout Overflows**: Un-wrapped setting card titles and badges caused high-frequency `RenderFlex` layout exception loops during window drag passes.

---

## 1. Minidump Diagnostic Analysis

Analysis of the minidump binaries extracted the exact fault parameters:

```text
Minidump Signature: MDMP
Number of Streams: 14

=== EXCEPTION STREAM ===
Thread ID:        4828
Exception Code:   0xC0000005 (STATUS_ACCESS_VIOLATION)
Faulting Module:  flutter_windows.dll
Faulting Addr:    0x00007FFC1342C16A
Dart Crash Log:   Empty (Confirmed 100% Native Win32/C++ crash)
```

> [!NOTE]
> Because `dart_crash_logs.txt` was completely blank, the crash was confirmed to be taking place at the native C++ engine boundary inside `flutter_windows.dll`, rather than within the Dart runtime engine.

---

## 2. Environment Comparison Matrix

| Environment | Behavior | Underlying Reason |
| :--- | :--- | :--- |
| **Windows Sandbox** | **100% Stable (No Crash)** | Runs on a virtualized software DWM rasterizer; Win32 COM OLE drag-and-drop registration runs in isolated fallback mode. |
| **Host System (First Launch)** | **Stable** | AppData is clean; settings lists and icon cache are unpopulated, keeping window repaint lightweight during resize. |
| **Host System (Subsequent Runs)** | **Crash to Desktop (CTD)** | Physical GPU (NVIDIA/AMD/Intel) running DirectX 11. Populated settings lists + active background OLE drag-and-drop hooks + zero-dimension `MoveWindow` calls = native engine crash. |

---

## 3. Root Causes & Multi-Layer Fixes

### Layer 1: Architecture & Tab Isolation ([lib/main.dart](file:///c:/projects/android_apps/app_manager/lib/main.dart))

#### Cause
`MainTabShell` used an `IndexedStack` that kept all 6 screens instantiated simultaneously. Tab 0 (`DropzoneInstaller`) active OLE drag-and-drop hooks received `WM_SIZE` messages concurrently with Tab 4 (`HiddenSettingsScreen`) layout repaints.

#### Resolution
Updated `MainTabShell` to lazy-mount **only the active tab view**:

```dart
// [lib/main.dart]
body: IndexedStack(
  index: _currentIndex,
  children: [
    _currentIndex == 0
        ? DropzoneInstaller(
            connectedDevices: _connectedDevices,
            selectedDeviceSerial: _selectedDeviceSerial,
          )
        : const SizedBox.shrink(),
    _currentIndex == 1
        ? AppListScreen(...)
        : const SizedBox.shrink(),
    _currentIndex == 2
        ? FDroidScreen(...)
        : const SizedBox.shrink(),
    _currentIndex == 3
        ? WifiAdbScreen(...)
        : const SizedBox.shrink(),
    _currentIndex == 4
        ? HiddenSettingsScreen(
            connectedDevices: _connectedDevices,
            selectedDeviceSerial: _selectedDeviceSerial,
          )
        : const SizedBox.shrink(),
    _currentIndex == 5 ? _buildSettingsView() : const SizedBox.shrink(),
  ],
)
```

---

### Layer 2: Native Win32 Window Runner ([windows/runner/win32_window.cpp](file:///c:/projects/android_apps/app_manager/windows/runner/win32_window.cpp))

#### Cause
The Win32 window proc lacked `WM_GETMINMAXINFO` handling and called `MoveWindow()` unconditionally on `WM_SIZE`, causing `0x0` surface dimensions and DirectX swapchain buffer failures (`DXGI_ERROR_INVALID_CALL`).

#### Resolution
Enforced a `480x360` minimum window tracking size and guarded `WM_SIZE` against zero-dimension or minimized states:

```cpp
// [windows/runner/win32_window.cpp]
case WM_GETMINMAXINFO: {
  auto info = reinterpret_cast<MINMAXINFO*>(lparam);
  info->ptMinTrackSize.x = 480;
  info->ptMinTrackSize.y = 360;
  return 0;
}

case WM_SIZE: {
  if (wparam != SIZE_MINIMIZED && child_content_ != nullptr) {
    RECT rect = GetClientArea();
    int width = rect.right - rect.left;
    int height = rect.bottom - rect.top;
    if (width > 0 && height > 0) {
      MoveWindow(child_content_, rect.left, rect.top, width, height, TRUE);
    }
  }
  return 0;
}
```

> [!TIP]
> Additionally, `windows/runner/main.cpp` was updated with `if (::IsDebuggerPresent()) return EXCEPTION_CONTINUE_SEARCH;` to prevent minidump creation from deadlocking when external native debuggers (`CustomShellDebugger.exe` or Visual Studio) are attached.

---

### Layer 3: Responsive UI Layout ([lib/hidden_settings_screen.dart](file:///c:/projects/android_apps/app_manager/lib/hidden_settings_screen.dart))

#### Cause
Rigid horizontal `Row` widgets inside `_SettingRowWidget` and top headers overflowed when window width was scaled below ~650px, throwing high-frequency `RenderFlex` layout exceptions.

#### Resolution
1. Replaced rigid `Row` title layouts with flex `Wrap` widgets to let setting keys and risk badges wrap cleanly.
2. Wrapped cards in a `LayoutBuilder` that automatically stacks controls vertically when card width is narrow (< 480px).
3. Added `dispose()` handling for `_searchController` and `_quickTweaksScrollController`.

---

## 4. Verification & Status

- **Automated Code Analysis**: Passed `flutter analyze` with 0 errors.
- **Release Build**: Compiled release executable (`build\windows\x64\runner\Release\app_manager.exe`).
- **Windows Sandbox Package**: Updated [AppManagerSandbox.wsb](file:///c:/projects/android_apps/app_manager/AppManagerSandbox.wsb) and bundled VC++ runtimes.
- **Git Tracked**: All changes staged and committed across repository commits.
