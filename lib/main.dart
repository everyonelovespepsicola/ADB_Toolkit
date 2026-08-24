import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'adb_manager.dart';
import 'dropzone_installer.dart';
import 'app_list_screen.dart';
import 'file_manager_screen.dart';
import 'wifi_adb_screen.dart';
import 'fdroid_screen.dart';
import 'hidden_settings_screen.dart';
import 'translation_service.dart';
import 'theme.dart';

void _logCrash(dynamic error, StackTrace? stackTrace) async {
  try {
    final envAppData = Platform.environment['APPDATA'];
    if (envAppData != null) {
      final crashDir = Directory("$envAppData\\com.adbtoolkit.app\\adb_toolkit\\crashes");
      if (!await crashDir.exists()) {
        await crashDir.create(recursive: true);
      }
      final logFile = File("${crashDir.path}\\dart_crash_logs.txt");
      final now = DateTime.now().toIso8601String();
      final content = "[$now] ERROR: $error\nSTACKTRACE:\n$stackTrace\n----------------------------------------\n\n";
      await logFile.writeAsString(content, mode: FileMode.append);
    }
  } catch (_) {}
}

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _logCrash(details.exception, details.stack);
  };

  runZonedGuarded(() {
    runApp(const AdbToolkitApp());
  }, (error, stackTrace) {
    _logCrash(error, stackTrace);
  });
}

class AdbToolkitApp extends StatelessWidget {
  const AdbToolkitApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const materialTheme = MaterialTheme(TextTheme());

    return MaterialApp(
      title: 'ADB Toolkit',
      debugShowCheckedModeBanner: false,
      theme: materialTheme.dark(),
      home: const MainTabShell(),
    );
  }
}

class MainTabShell extends StatefulWidget {
  const MainTabShell({Key? key}) : super(key: key);

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> {
  int _currentIndex = 0;
  List<DeviceInfo> _connectedDevices = [];
  String? _selectedDeviceSerial;
  Timer? _devicePollTimer;
  String _adbPathStatus = "Resolving portable ADB...";
  bool _showTooltips = false;

  @override
  void initState() {
    super.initState();
    _initAdb();
    _refreshDevices();
    _devicePollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshDevices());
  }

  @override
  void dispose() {
    _devicePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAdb() async {
    try {
      final path = await AdbManager.getAdbExecutablePath();
      if (mounted) {
        setState(() {
          _adbPathStatus = path != null ? "Portable ADB Active: $path" : "Portable ADB Ready";
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _adbPathStatus = "Portable ADB Ready (System/Local)";
        });
      }
    }
  }

  Future<void> _refreshDevices() async {
    final list = await AdbManager.getConnectedDevices();
    if (mounted) {
      setState(() {
        _connectedDevices = list;
        if (list.isNotEmpty) {
          if (_selectedDeviceSerial == null || !list.any((d) => d.serial == _selectedDeviceSerial)) {
            _selectedDeviceSerial = list.first.serial;
          }
        } else {
          _selectedDeviceSerial = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 2,
        title: Row(
          children: [
            const Icon(Icons.phonelink_setup, color: Color(0xFF4DEAEA), size: 24),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ADB Toolkit',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  _adbPathStatus,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Device selector dropdown in app bar
          if (_connectedDevices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Theme.of(context).colorScheme.primary, size: 10),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: _selectedDeviceSerial,
                      underline: const SizedBox(),
                      dropdownColor: Theme.of(context).colorScheme.primaryContainer,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                      items: _connectedDevices.map((d) {
                        return DropdownMenuItem(
                          value: d.serial,
                          child: Text("${d.displayName} [${d.isWifi ? 'Wi-Fi' : 'USB'}]"),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedDeviceSerial = val),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(right: 12.0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.error, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, color: Theme.of(context).colorScheme.error, size: 10),
                  const SizedBox(width: 6),
                  Text('No Devices Connected', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
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
              ? AppListScreen(
                  connectedDevices: _connectedDevices,
                  selectedDeviceSerial: _selectedDeviceSerial,
                )
              : const SizedBox.shrink(),
          _currentIndex == 2
              ? FileManagerScreen(
                  connectedDevices: _connectedDevices,
                  selectedDeviceSerial: _selectedDeviceSerial,
                )
              : const SizedBox.shrink(),
          _currentIndex == 3
              ? FDroidScreen(
                  connectedDevices: _connectedDevices,
                  selectedDeviceSerial: _selectedDeviceSerial,
                )
              : const SizedBox.shrink(),
          _currentIndex == 4
              ? WifiAdbScreen(
                  connectedDevices: _connectedDevices,
                  onDevicesUpdated: _refreshDevices,
                )
              : const SizedBox.shrink(),
          _currentIndex == 5
              ? HiddenSettingsScreen(
                  connectedDevices: _connectedDevices,
                  selectedDeviceSerial: _selectedDeviceSerial,
                  showTooltips: _showTooltips,
                )
              : const SizedBox.shrink(),
          _currentIndex == 6 ? _buildSettingsView() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildDockButton(
                label: '📥 INSTALLER',
                index: 0,
                activeColor: Colors.white,
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '📱 APP MANAGER',
                index: 1,
                activeColor: Colors.white,
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '📁 FILE MANAGER',
                index: 2,
                activeColor: Colors.white,
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '🛍️ F-DROID STORE',
                index: 3,
                activeColor: Colors.white,
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '📶 WI-FI ADB',
                index: 4,
                activeColor: Colors.white,
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '🛠️ HIDDEN SETTINGS',
                index: 5,
                activeColor: Colors.white,
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '⚙️ SETTINGS',
                index: 6,
                activeColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDockButton({
    required String label,
    required int index,
    required Color activeColor,
  }) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        alignment: Alignment.center,
        margin: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF242424),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : const Color(0xFF9CA3AF),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SETTINGS & PORTABLE ADB ENVIRONMENT',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.language, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'APP DISPLAY LANGUAGE (DYNAMIC ON-THE-FLY AUTO-TRANSLATE):',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Current Mode: ${TranslationService().selectedLanguageCode == 'auto' ? "🌐 Auto-Detecting Windows OS Default (${TranslationService().effectiveLanguageCode.toUpperCase()})" : "Selected ${TranslationService().selectedLanguageCode.toUpperCase()}"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF383838)),
                  ),
                  child: DropdownButton<String>(
                    value: TranslationService().selectedLanguageCode,
                    underline: const SizedBox(),
                    dropdownColor: const Color(0xFF242424),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    isExpanded: true,
                    items: AppLanguageOption.options.map((opt) {
                      return DropdownMenuItem<String>(
                        value: opt.code,
                        child: Row(
                          children: [
                            Text(opt.flagEmoji, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(opt.displayName, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          TranslationService().setLanguage(val);
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHOW SETTING EXPLANATION TOOLTIPS:',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _showTooltips
                            ? '🟢 Enabled: Explanatory tooltips & descriptions will appear next to Android settings keys across the app.'
                            : '🔴 Disabled (Default): Tooltip descriptions are hidden for a clean, minimal interface.',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: _showTooltips,
                  activeColor: const Color(0xFF00FF66),
                  onChanged: (val) => setState(() => _showTooltips = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PORTABLE ADB BINARY PATH:', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(_adbPathStatus, style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                  onPressed: _initAdb,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Re-resolve Local ADB', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ANDROID 15 INSTALLATION FLAGS:', style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  'All APK installations automatically execute with flags:\n  adb install -r -g --bypass-low-target-sdk-block <apk_path>\n\n-r: Replace existing app\n-g: Auto-grant all requested runtime permissions\n--bypass-low-target-sdk-block: Bypasses Android 14/15 legacy Target SDK blocks',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LOCAL APPDATA STORAGE & CACHE:', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Clears cached app icon PNGs and temporary crash dump files from AppData while preserving platform-tools ADB executables.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
                  onPressed: () async {
                    try {
                      final envAppData = Platform.environment['APPDATA'];
                      if (envAppData != null) {
                        final appDataPath = "$envAppData\\com.adbtoolkit.app\\adb_toolkit";
                        final appDataDir = Directory(appDataPath);
                        if (await appDataDir.exists()) {
                          await for (final entity in appDataDir.list()) {
                            if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
                              await entity.delete();
                            }
                          }
                        }
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🟢 AppData icon cache successfully cleared!')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('🔴 Error clearing cache: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.cleaning_services, size: 16),
                  label: const Text('CLEAR LOCAL APPDATA CACHE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CRASH DIAGNOSTICS & MINIDUMP LOGGER:', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Automated 2-Layer Crash Handler:\n  • Level 1 (Dart/Flutter): Intercepts uncaught Dart exceptions to dart_crash_logs.txt.\n  • Level 2 (Win32 C++): MiniDumpWriteDump writes native .dmp minidumps for Visual Studio / x64dbg.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF242424), foregroundColor: Colors.white),
                      onPressed: () async {
                        try {
                          final envAppData = Platform.environment['APPDATA'];
                          if (envAppData != null) {
                            final crashPath = "$envAppData\\com.adbtoolkit.app\\adb_toolkit\\crashes";
                            final crashDir = Directory(crashPath);
                            if (!await crashDir.exists()) {
                              await crashDir.create(recursive: true);
                            }
                            await Process.run('explorer.exe', [crashPath]);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔴 Unable to open folder: $e')));
                          }
                        }
                      },
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('OPEN CRASH DUMPS FOLDER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                      onPressed: () async {
                        try {
                          final envAppData = Platform.environment['APPDATA'];
                          if (envAppData != null) {
                            final logFile = File("$envAppData\\com.adbtoolkit.app\\adb_toolkit\\crashes\\dart_crash_logs.txt");
                            final logs = await logFile.exists() ? await logFile.readAsString() : "No Dart crash logs recorded yet!";
                            if (mounted) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF181818),
                                  title: const Text('DART CRASH LOGS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  content: SizedBox(
                                    width: 600,
                                    height: 350,
                                    child: SingleChildScrollView(
                                      child: SelectableText(logs, style: const TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace', fontSize: 11)),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        if (ctx.mounted && Navigator.canPop(ctx)) {
                                          Navigator.of(ctx).pop();
                                        }
                                      },
                                      child: const Text('Close', style: TextStyle(color: Colors.grey)),
                                    ),
                                  ],
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔴 Error reading logs: $e')));
                          }
                        }
                      },
                      icon: const Icon(Icons.bug_report, size: 16),
                      label: const Text('VIEW DART CRASH LOGS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
