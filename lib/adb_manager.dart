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
  final int sdkVersion; // e.g. 29 for Android 10, 34 for Android 14
  final String androidVersion; // e.g. "10", "14", "15"

  DeviceInfo({
    required this.serial,
    required this.state,
    required this.model,
    required this.product,
    required this.isWifi,
    this.sdkVersion = 30,
    this.androidVersion = "11",
  });

  String get displayName {
    final verStr = androidVersion.isNotEmpty ? " [Android $androidVersion]" : "";
    if (model.isNotEmpty) return "$model$verStr ($serial)";
    return "$serial$verStr";
  }
}

class AppPackageInfo {
  final String packageName;
  final String apkPath;
  final bool isSystem;
  final bool isDisabled;
  final int installTimestamp;

  AppPackageInfo({
    required this.packageName,
    required this.apkPath,
    required this.isSystem,
    required this.isDisabled,
    this.installTimestamp = 0,
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

  // List connected devices (USB & Wi-Fi) with Android Version & SDK detection
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
            if (state != "device") continue;

            String model = "";
            String product = "";
            int sdkVer = 30;
            String androidVer = "11";

            for (final p in parts) {
              if (p.startsWith('model:')) model = p.substring(6);
              if (p.startsWith('product:')) product = p.substring(8);
            }

            // Query Android SDK Level and OS Release Version
            try {
              final sdkRes = await runAdb(['-s', serial, 'shell', 'getprop', 'ro.build.version.sdk']);
              final sdkStr = sdkRes.stdout.toString().trim();
              if (sdkStr.isNotEmpty) {
                sdkVer = int.tryParse(sdkStr) ?? 30;
              }

              final relRes = await runAdb(['-s', serial, 'shell', 'getprop', 'ro.build.version.release']);
              final relStr = relRes.stdout.toString().trim();
              if (relStr.isNotEmpty) {
                androidVer = relStr;
              }
            } catch (_) {}

            final isWifi = serial.contains(':') || serial.contains('.');
            devices.add(
              DeviceInfo(
                serial: serial,
                state: state,
                model: model,
                product: product,
                isWifi: isWifi,
                sdkVersion: sdkVer,
                androidVersion: androidVer,
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

  // Install APK with version-aware flags (Android 14+ vs Android 10-13)
  static Future<Map<String, dynamic>> installApk(String serial, String apkPath, {int? sdkVersion}) async {
    try {
      final List<String> args = ['-s', serial, 'install', '-r', '-g'];

      // Include --bypass-low-target-sdk-block only on Android 14+ (API 34+)
      if (sdkVersion != null && sdkVersion >= 34) {
        args.add('--bypass-low-target-sdk-block');
      }

      args.add(apkPath);

      var res = await runAdb(args);
      var out = res.stdout.toString() + res.stderr.toString();

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
      // Pre-fetch real file modification/install timestamps from Android /data/app
      final Map<String, int> pathTimestamps = {};
      try {
        final statRes = await runAdb(['-s', serial, 'shell', 'stat -c "%n %Y" /data/app/*/*.apk /data/app/*/*/*.apk /system/app/*/*.apk /system/priv-app/*/*.apk 2>/dev/null']);
        if (statRes.exitCode == 0) {
          final statLines = statRes.stdout.toString().split('\n');
          for (final sLine in statLines) {
            final parts = sLine.trim().split(' ');
            if (parts.length >= 2) {
              final apkP = parts[0].trim();
              final ts = int.tryParse(parts[1].trim());
              if (ts != null) pathTimestamps[apkP] = ts;
            }
          }
        }
      } catch (_) {}

      final flag = filter == 'system' ? '-s' : (filter == 'disabled' ? '-d' : '-3');
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'list', 'packages', '-f', flag]);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        int fallbackIndex = 0;
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('package:')) {
            final raw = trimmed.substring(8);
            final eqIdx = raw.lastIndexOf('=');
            if (eqIdx != -1) {
              final path = raw.substring(0, eqIdx);
              final pkg = raw.substring(eqIdx + 1);
              fallbackIndex++;

              // Use real stat timestamp if available, fallback to index
              int realTimestamp = pathTimestamps[path] ?? fallbackIndex;

              list.add(
                AppPackageInfo(
                  packageName: pkg,
                  apkPath: path,
                  isSystem: filter == 'system',
                  isDisabled: filter == 'disabled',
                  installTimestamp: realTimestamp,
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

  static final Map<String, List<int>?> _memoryIconCache = {};

  // Fetch official HD App Icon from Google Play Store with persistent local disk caching
  static Future<List<int>?> getCachedPlayStoreIconBytes(String packageName) async {
    if (_memoryIconCache.containsKey(packageName)) {
      return _memoryIconCache[packageName];
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      final iconCacheDir = Directory("${appDir.path}\\icon_cache");
      if (!iconCacheDir.existsSync()) iconCacheDir.createSync(recursive: true);

      final cachedFile = File("${iconCacheDir.path}\\$packageName.png");
      if (cachedFile.existsSync()) {
        final bytes = await cachedFile.readAsBytes();
        _memoryIconCache[packageName] = bytes;
        return bytes;
      }

      // Download from Google Play Store Web
      final url = Uri.parse("https://play.google.com/store/apps/details?id=$packageName");
      final response = await http.get(
        url,
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final html = response.body;
        final regExp = RegExp(r'https:\/\/play-lh\.googleusercontent\.com\/[a-zA-Z0-9_\-=\/]+');
        final match = regExp.firstMatch(html);
        if (match != null) {
          final imageUrl = match.group(0)!;
          final imgResponse = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 4));
          if (imgResponse.statusCode == 200) {
            final imgBytes = imgResponse.bodyBytes;
            await cachedFile.writeAsBytes(imgBytes);
            _memoryIconCache[packageName] = imgBytes;
            return imgBytes;
          }
        }
      }
    } catch (_) {}

    _memoryIconCache[packageName] = null;
    return null;
  }

  // Set App as Enterprise Device Owner via ADB (dpm set-device-owner)
  static Future<Map<String, dynamic>> setDeviceOwner(String serial, String packageName, [String? adminComponent]) async {
    try {
      final receiver = adminComponent ?? "$packageName/.AdminReceiver";
      final res = await runAdb(['-s', serial, 'shell', 'dpm', 'set-device-owner', receiver]);
      final out = res.stdout.toString() + res.stderr.toString();
      final success = out.contains("Success") || out.contains("active admin set");
      return {"success": success, "message": out.trim()};
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // List Active Device Owners on phone
  static Future<String> getDeviceOwners(String serial) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'dpm', 'list-owners']);
      return (res.stdout.toString() + res.stderr.toString()).trim();
    } catch (e) {
      return e.toString();
    }
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

  // Get all key-value settings for a namespace (global, secure, or system)
  static Future<Map<String, String>> getSettingsList(String serial, String namespace) async {
    final Map<String, String> settingsMap = {};
    try {
      final res = await runAdb(['-s', serial, 'shell', 'settings', 'list', namespace]);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx != -1) {
            final key = trimmed.substring(0, eqIdx);
            final val = trimmed.substring(eqIdx + 1);
            settingsMap[key] = val;
          }
        }
      }
    } catch (_) {}
    return settingsMap;
  }

  // Put / Update a specific setting key-value
  static Future<bool> putSetting(String serial, String namespace, String key, String value) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'settings', 'put', namespace, key, value]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Get a single setting value
  static Future<String?> getSetting(String serial, String namespace, String key) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'settings', 'get', namespace, key]);
      if (res.exitCode == 0) {
        final val = res.stdout.toString().trim();
        if (val != 'null') return val;
      }
    } catch (_) {}
    return null;
  }

  // Grant any elevated Android permission via ADB (pm grant)
  static Future<Map<String, dynamic>> grantPermission(String serial, String packageName, String permission) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'grant', packageName, permission.trim()]);
      final out = res.stdout.toString() + res.stderr.toString();
      final success = res.exitCode == 0 && !out.contains("Error") && !out.contains("Exception");
      return {"success": success, "message": out.isEmpty ? "Permission granted successfully!" : out.trim()};
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // Revoke any elevated Android permission via ADB (pm revoke)
  static Future<Map<String, dynamic>> revokePermission(String serial, String packageName, String permission) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'pm', 'revoke', packageName, permission.trim()]);
      final out = res.stdout.toString() + res.stderr.toString();
      final success = res.exitCode == 0 && !out.contains("Error") && !out.contains("Exception");
      return {"success": success, "message": out.isEmpty ? "Permission revoked successfully!" : out.trim()};
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // Read text file content directly from Android phone
  static Future<String?> readPhoneFile(String serial, String filePath) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'cat', filePath]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString();
        if (!out.contains("No such file or directory") && !out.contains("Permission denied") && out.trim().isNotEmpty) {
          return out;
        }
      }
    } catch (_) {}
    return null;
  }

  // Write text content directly to a file on the Android phone using base64 decoding
  static Future<bool> writePhoneFile(String serial, String filePath, String content) async {
    try {
      final b64 = base64Encode(utf8.encode(content));
      final res = await runAdb(['-s', serial, 'shell', 'echo "$b64" | base64 -d > "$filePath"']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Browse files/folders on phone over ADB shell ls -la
  static Future<List<AdbFileEntry>> listDirectory(String serial, String remotePath) async {
    final entries = <AdbFileEntry>[];
    try {
      final cleanPath = remotePath.endsWith('/') ? remotePath : '$remotePath/';
      final res = await runAdb(['-s', serial, 'shell', 'ls', '-la', cleanPath]);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('total ')) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 8) {
            final permissions = parts[0];
            final isDirectory = permissions.startsWith('d') || permissions.startsWith('l');
            final nameIndex = parts.length > 8 ? 8 : 7;
            final name = parts.sublist(nameIndex).join(' ');
            if (name == '.' || name == '..') continue;

            final sizeString = parts[4];
            final size = int.tryParse(sizeString) ?? 0;
            final date = "${parts[5]} ${parts[6]} ${parts[7]}";

            entries.add(AdbFileEntry(
              name: name,
              path: "$cleanPath$name",
              isDirectory: isDirectory,
              sizeBytes: size,
              modifiedDate: date,
              permissions: permissions,
            ));
          }
        }
      }
    } catch (_) {}

    // Sort: Folders first (A-Z), then Files (A-Z)
    entries.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  // Delete file or folder on phone via ADB (rm -rf)
  static Future<bool> deleteRemotePath(String serial, String remotePath) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'rm', '-rf', remotePath]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Create new folder on phone via ADB (mkdir -p)
  static Future<bool> createRemoteDirectory(String serial, String remotePath) async {
    try {
      final res = await runAdb(['-s', serial, 'shell', 'mkdir', '-p', remotePath]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Push local PC file to Phone over ADB
  static Future<bool> pushFileToPhone(String serial, String localPath, String remotePath) async {
    try {
      final res = await runAdb(['-s', serial, 'push', localPath, remotePath]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Pull remote Phone file/folder to PC over ADB
  static Future<bool> pullFileFromPhone(String serial, String remotePath, String localPath) async {
    try {
      final res = await runAdb(['-s', serial, 'pull', remotePath, localPath]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // Backup /sdcard/Android/data/<packageName>/ to target local directory
  static Future<Map<String, dynamic>> backupAppData(String serial, String packageName, String targetLocalDir) async {
    try {
      final remoteSource = "/sdcard/Android/data/$packageName";
      final saveFolder = Directory("$targetLocalDir/$packageName");
      if (!await saveFolder.exists()) {
        await saveFolder.create(recursive: true);
      }

      final res = await runAdb(['-s', serial, 'pull', remoteSource, saveFolder.path]);
      final out = res.stdout.toString() + res.stderr.toString();
      final success = res.exitCode == 0 || out.contains("pulled") || out.contains("files pulled");
      return {
        "success": success,
        "message": success ? "🟢 App data backed up to ${saveFolder.path}!" : "🔴 Backup failed: $out",
        "path": saveFolder.path,
      };
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // Restore local app data backup folder back to /sdcard/Android/data/<packageName>/
  static Future<Map<String, dynamic>> restoreAppData(String serial, String packageName, String localSourceDir) async {
    try {
      final remoteDest = "/sdcard/Android/data/$packageName";
      // Ensure target directory exists on phone
      await createRemoteDirectory(serial, remoteDest);

      final res = await runAdb(['-s', serial, 'push', "$localSourceDir/.", remoteDest]);
      final out = res.stdout.toString() + res.stderr.toString();
      final success = res.exitCode == 0 || out.contains("pushed") || out.contains("files pushed");
      return {
        "success": success,
        "message": success ? "🟢 App data restored to $remoteDest!" : "🔴 Restore failed: $out",
      };
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }
}

class AdbFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final String modifiedDate;
  final String permissions;

  AdbFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedDate,
    required this.permissions,
  });

  String get formattedSize {
    if (isDirectory) return "Folder";
    if (sizeBytes < 1024) return "$sizeBytes B";
    if (sizeBytes < 1024 * 1024) return "${(sizeBytes / 1024).toStringAsFixed(1)} KB";
    if (sizeBytes < 1024 * 1024 * 1024) return "${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }
}
