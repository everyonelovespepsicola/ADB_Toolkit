import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'adb_manager.dart';

class ApkInstallItem {
  final String fileName;
  final String filePath;
  String status; // "pending", "installing", "success", "failed"
  String log;

  ApkInstallItem({
    required this.fileName,
    required this.filePath,
    this.status = "pending",
    this.log = "Ready to install",
  });
}

class DropzoneInstaller extends StatefulWidget {
  final List<DeviceInfo> connectedDevices;
  final String? selectedDeviceSerial;

  const DropzoneInstaller({
    Key? key,
    required this.connectedDevices,
    this.selectedDeviceSerial,
  }) : super(key: key);

  @override
  State<DropzoneInstaller> createState() => _DropzoneInstallerState();
}

class _DropzoneInstallerState extends State<DropzoneInstaller> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isDragging = false;
  bool _batchAllDevices = false;
  bool _setAsDeviceOwner = false;
  final List<ApkInstallItem> _queue = [];
  bool _isInstalling = false;

  void _addApkFiles(List<String> paths) {
    setState(() {
      for (final p in paths) {
        if (p.toLowerCase().endsWith('.apk')) {
          final fileName = p.split(RegExp(r'[/\\]')).last;
          if (!_queue.any((item) => item.filePath == p)) {
            _queue.add(ApkInstallItem(fileName: fileName, filePath: p));
          }
        }
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
      allowMultiple: true,
    );

    if (result != null) {
      final paths = result.paths.whereType<String>().toList();
      _addApkFiles(paths);
    }
  }

  Future<void> _startInstallation() async {
    if (_queue.isEmpty || _isInstalling) return;

    if (widget.connectedDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ No Android devices connected via USB or Wi-Fi!')),
      );
      return;
    }

    setState(() => _isInstalling = true);

    final targetDevices = _batchAllDevices
        ? widget.connectedDevices
        : widget.connectedDevices.where((d) => d.serial == widget.selectedDeviceSerial).toList();

    final activeTarget = targetDevices.isNotEmpty ? targetDevices : [widget.connectedDevices.first];

    for (final item in _queue) {
      if (item.status == "success") continue;

      setState(() {
        item.status = "installing";
        item.log = "Installing on ${activeTarget.length} device(s)...";
      });

      for (final dev in activeTarget) {
        final result = await AdbManager.installApk(dev.serial, item.filePath, sdkVersion: dev.sdkVersion);
        setState(() {
          if (result['success'] == true) {
            item.status = "success";
            item.log = "🟢 Installed on ${dev.displayName}";
          } else {
            item.status = "failed";
            item.log = "🔴 Failed on ${dev.displayName}: ${result['message']}";
          }
        });

        // Optional: Execute Enterprise Device Owner Setup (dpm set-device-owner)
        if (result['success'] == true && _setAsDeviceOwner) {
          // Infer package name from filename or APK path
          final rawName = item.fileName.replaceAll('.apk', '');
          final dpmResult = await AdbManager.setDeviceOwner(dev.serial, rawName);
          setState(() {
            if (dpmResult['success'] == true) {
              item.log += " | 👑 Device Owner Granted!";
            } else {
              item.log += " | ⚠️ DPM: ${dpmResult['message']}";
            }
          });
        }
      }
    }

    setState(() => _isInstalling = false);
  }

  void _clearQueue() {
    setState(() {
      _queue.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Batch Mode & Controls Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INSTALL TARGET DEVICE:',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _batchAllDevices
                                ? "🚀 ALL CONNECTED DEVICES (${widget.connectedDevices.length})"
                                : (widget.selectedDeviceSerial ?? "Select target device above"),
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Batch All Devices', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12)),
                        const SizedBox(width: 6),
                        Switch(
                          value: _batchAllDevices,
                          activeColor: Theme.of(context).colorScheme.primary,
                          onChanged: (val) => setState(() => _batchAllDevices = val),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 16),
                Row(
                  children: [
                    const Icon(Icons.security, color: Color(0xFFFFB74D), size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Set as Full Enterprise Device Owner (dpm set-device-owner)',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Switch(
                      value: _setAsDeviceOwner,
                      activeColor: const Color(0xFFFFB74D),
                      onChanged: (val) {
                        setState(() => _setAsDeviceOwner = val);
                        if (val) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('👑 Device Owner Mode Enabled! App will execute dpm set-device-owner after installation.'),
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Drag and Drop Zone
          DropTarget(
            onDragEntered: (details) => setState(() => _isDragging = true),
            onDragExited: (details) => setState(() => _isDragging = false),
            onDragDone: (details) {
              setState(() => _isDragging = false);
              final paths = details.files.map((f) => f.path).toList();
              _addApkFiles(paths);
            },
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: _isDragging ? const Color(0xFF162A20) : const Color(0xFF181818),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isDragging ? const Color(0xFF00FF66) : const Color(0xFF2D2D2D),
                  width: _isDragging ? 2.5 : 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_upload,
                    size: 52,
                    color: Color(0xFF00FF66),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isDragging ? "DROP APK FILES HERE!" : "Drag & Drop APK files here to Install",
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Auto-grants permissions & bypasses Android 15 target SDK block",
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse Files', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Queue List & Install Button
          if (_queue.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "APK INSTALL QUEUE (${_queue.length})",
                  style: const TextStyle(color: Color(0xFF8090A0), fontSize: 12, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _clearQueue,
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                  label: const Text('Clear Queue', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _queue.length,
              itemBuilder: (ctx, idx) {
                final item = _queue[idx];
                Color badgeColor = Colors.grey;
                IconData badgeIcon = Icons.hourglass_empty;

                if (item.status == "installing") {
                  badgeColor = const Color(0xFFFFB74D);
                  badgeIcon = Icons.sync;
                } else if (item.status == "success") {
                  badgeColor = const Color(0xFF00FF66);
                  badgeIcon = Icons.check_circle;
                } else if (item.status == "failed") {
                  badgeColor = const Color(0xFFFF5252);
                  badgeIcon = Icons.error;
                }

                return Card(
                  color: const Color(0xFF181818),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(badgeIcon, color: badgeColor),
                    title: Text(item.fileName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(item.log, style: TextStyle(color: badgeColor, fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                      onPressed: () {
                        setState(() => _queue.removeAt(idx));
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF66),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isInstalling ? null : _startInstallation,
                icon: _isInstalling
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.play_arrow, size: 22),
                label: Text(
                  _isInstalling ? "INSTALLING APKs..." : "START BATCH INSTALLATION",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
