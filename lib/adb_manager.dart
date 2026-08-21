import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class DeviceInfo {
  final String serial;
  final String state; // e.g. "device", "unauthorized", "offline"
  final String model;
  final String product;
  final bool isWifi;

  DeviceInfo({
    required this.serial,
    required this.state,
    required this.model,
    required this.product,
    required this.isWifi,
  });

  String get displayName {
    if (model.isNotEmpty) return "$model ($serial)";
    return serial;
  }
}

class AppPackageInfo {
  final String packageName;
  final String apkPath;
  final bool isSystem;
  final bool isDisabled;

  AppPackageInfo({
    required this.packageName,
    required this.apkPath,
    required this.isSystem,
    required this.isDisabled,
  });

  String get appName {
    final parts = packageName.split('.');
    if (parts.length > 1) {
      final name = parts.last;
      return name[0].toUpperCase() + name.substring(1);
    }
    return packageName;
  }
}

class AdbManager {
  static String? _resolvedAdbPath;
  static bool _isInitializing = false;

  // Resolves or downloads self-contained local adb.exe
  static Future<String?> getAdbExecutablePath() async {
    if (_resolvedAdbPath != null && File(_resolvedAdbPath!).existsSync()) {
      return _resolvedAdbPath;
    }

    if (_isInitializing) {
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_resolvedAdbPath != null) return _resolvedAdbPath;
    }

    _isInitializing = true;

    try {
      final appDir = await getApplicationSupportDirectory();
      final localAdbDir = Directory("${appDir.path}\\platform-tools");
      final localAdbExe = File("${localAdbDir.path}\\adb.exe");

      // 1. Check local app directory first
      if (localAdbExe.existsSync()) {
        _resolvedAdbPath = localAdbExe.path;
        _isInitializing = false;
        return _resolvedAdbPath;
      }

      // 2. Check WinGet package cache directory
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      if (localAppData.isNotEmpty) {
        final wingetDir = Directory("$localAppData\\Microsoft\\WinGet\\Packages");
        if (wingetDir.existsSync()) {
          try {
            final entities = wingetDir.listSync(recursive: true);
            for (final entity in entities) {
              if (entity is File && entity.path.endsWith("\\adb.exe") && entity.path.contains("Google.PlatformTools")) {
                // Copy adb.exe and companion DLLs to local app folder
                final sourceDir = entity.parent;
                if (!localAdbDir.existsSync()) localAdbDir.createSync(recursive: true);
                for (final file in sourceDir.listSync()) {
                  if (file is File) {
                    final targetName = file.path.split(Platform.pathSeparator).last;
                    file.copySync("${localAdbDir.path}\\$targetName");
                  }
                }
                _resolvedAdbPath = localAdbExe.path;
                _isInitializing = false;
                return _resolvedAdbPath;
              }
            }
          } catch (_) {}
        }
      }

      // 3. Check system PATH
      try {
        final result = await Process.run('where.exe', ['adb']);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          final firstLine = result.stdout.toString().trim().split('\r\n')[0];
          if (File(firstLine).existsSync()) {
            _resolvedAdbPath = firstLine;
            _isInitializing = false;
            return _resolvedAdbPath;
          }
        }
      } catch (_) {}

      // 4. Portable Download Fallback: Download Google's official platform-tools zip
      final zipUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip";
      final response = await http.get(Uri.parse(zipUrl));
      if (response.statusCode == 200) {
        final archive = ZipDecoder().decodeBytes(response.bodyBytes);
        if (!localAdbDir.existsSync()) localAdbDir.createSync(recursive: true);
        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            final outFile = File("${appDir.path}\\$filename");
            outFile.createSync(recursive: true);
            outFile.writeAsBytesSync(data);
          }
        }
        if (localAdbExe.existsSync()) {
          _resolvedAdbPath = localAdbExe.path;
          _isInitializing = false;
          return _resolvedAdbPath;
        }
      }
    } catch (_) {}

    _isInitializing = false;
    return _resolvedAdbPath ?? "adb";
  }

  // Executes ADB command with arguments
  static Future<ProcessResult> runAdb(List<String> args) async {
    final adbPath = await getAdbExecutablePath() ?? "adb";
    return await Process.run(adbPath, args);
  }

  // List connected devices (USB & Wi-Fi)
  static Future<List<DeviceInfo>> getConnectedDevices() async {
    final devices = <DeviceInfo>[];
    try {
      final res = await runAdb(['devices', '-l']);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('List of devices')) continue;

          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final serial = parts[0];
            final state = parts[1];
            String model = "";
            String product = "";

            for (final p in parts) {
              if (p.startsWith('model:')) model = p.substring(6);
              if (p.startsWith('product:')) product = p.substring(8);
            }

            final isWifi = serial.contains(':') || serial.contains('.');
            devices.add(
              DeviceInfo(
                serial: serial,
                state: state,
                model: model,
                product: product,
                isWifi: isWifi,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return devices;
  }

  // Wireless Wi-Fi ADB Pair (Android 11+)
  static Future<bool> pairWifi(String ipAndPort, String code) async {
    try {
      final res = await runAdb(['pair', ipAndPort.trim(), code.trim()]);
      final out = res.stdout.toString() + res.stderr.toString();
      return out.contains("Successfully paired") || out.contains("paired");
    } catch (_) {
      return false;
    }
  }

  // Wireless Wi-Fi ADB Connect
  static Future<bool> connectWifi(String ipAndPort) async {
    try {
      final res = await runAdb(['connect', ipAndPort.trim()]);
      final out = res.stdout.toString() + res.stderr.toString();
      return out.contains("connected to");
    } catch (_) {
      return false;
    }
  }

  // Switch USB device to TCP/IP Wireless Mode (Port 5555)
  static Future<bool> enableUsbTcpip(String serial, [int port = 5555]) async {
    try {
      final res = await runAdb(['-s', serial, 'tcpip', port.toString()]);
      final out = res.stdout.toString() + res.stderr.toString();
      return out.contains("restarting in TCP mode") || res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Auto-scan local Wi-Fi mDNS broadcasts for broadcasting phones
  static Future<List<String>> scanWifiMdns() async {
    final discovered = <String>[];
    try {
      final res = await runAdb(['mdns', 'services']);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.contains('_adb-tls-connect') || trimmed.contains('_adb-tls-pairing')) {
            discovered.add(trimmed);
          }
        }
      }
    } catch (_) {}
    return discovered;
  }

  // Install APK with Android 15 bypass flags
  static Future<Map<String, dynamic>> installApk(String serial, String apkPath) async {
    try {
      final res = await runAdb([
        '-s',
        serial,
        'install',
        '-r',
        '-g',
        '--bypass-low-target-sdk-block',
        apkPath,
      ]);

      final out = res.stdout.toString() + res.stderr.toString();
      final success = out.contains("Success") || res.exitCode == 0;
      return {"success": success, "message": out.trim()};
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // List installed packages on target device
  static Future<List<AppPackageInfo>> listPackages(String serial, {String filter = 'user'}) async {
    final list = <AppPackageInfo>[];
    try {
      final flag = filter == 'system' ? '-s' : (filter == 'disabled' ? '-d' : '-3');
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'list', 'packages', '-f', flag]);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('package:')) {
            final raw = trimmed.substring(8);
            final eqIdx = raw.lastIndexOf('=');
            if (eqIdx != -1) {
              final path = raw.substring(0, eqIdx);
              final pkg = raw.substring(eqIdx + 1);
              list.add(
                AppPackageInfo(
                  packageName: pkg,
                  apkPath: path,
                  isSystem: filter == 'system',
                  isDisabled: filter == 'disabled',
                ),
              );
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // Freeze / Disable package (pm disable-user --user 0)
  static Future<bool> disablePackage(String serial, String packageName) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'disable-user', '--user', '0', packageName]);
      final out = res.stdout.toString() + res.stderr.toString();
      return out.contains("new state: disabled") || out.contains("disabled-user");
    } catch (_) {
      return false;
    }
  }

  // Enable package (pm enable)
  static Future<bool> enablePackage(String serial, String packageName) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'enable', packageName]);
      final out = res.stdout.toString() + res.stderr.toString();
      return out.contains("new state: enabled");
    } catch (_) {
      return false;
    }
  }

  // Uninstall package (pm uninstall -k --user 0)
  static Future<bool> uninstallPackage(String serial, String packageName) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'uninstall', '-k', '--user', '0', packageName]);
      final out = res.stdout.toString() + res.stderr.toString();
      return out.contains("Success");
    } catch (_) {
      return false;
    }
  }

  static final Map<String, List<int>> _iconCache = {};

  // Extract App Icon bytes from target device APK
  static Future<List<int>?> getAppIconBytes(String serial, String packageName, String apkPath) async {
    final cacheKey = "$serial:$packageName";
    if (_iconCache.containsKey(cacheKey)) {
      return _iconCache[cacheKey];
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final tempApk = File("${tempDir.path}\\${packageName}_temp.apk");

      final pullRes = await runAdb(['-s', serial, 'pull', apkPath, tempApk.path]);
      if (pullRes.exitCode == 0 && tempApk.existsSync()) {
        final bytes = await tempApk.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        try { tempApk.deleteSync(); } catch (_) {}

        ArchiveFile? iconFile;
        for (final file in archive) {
          final name = file.name.toLowerCase();
          if ((name.contains('ic_launcher') || name.contains('icon') || name.contains('logo')) &&
              (name.endsWith('.png') || name.endsWith('.webp'))) {
            if (iconFile == null || name.contains('xxxhdpi') || name.contains('xxhdpi')) {
              iconFile = file;
            }
          }
        }

        if (iconFile != null) {
          final iconBytes = iconFile.content as List<int>;
          _iconCache[cacheKey] = iconBytes;
          return iconBytes;
        }
      }
    } catch (_) {}

    return null;
  }

  // Clear App Cache & Data (pm clear)
  static Future<bool> clearPackageData(String serial, String packageName) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'clear', packageName]);
      final out = res.stdout.toString() + res.stderr.toString();
      return out.contains("Success");
    } catch (_) {
      return false;
    }
  }
}
