import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'adb_manager.dart';

class FileManagerScreen extends StatefulWidget {
  final List<DeviceInfo> connectedDevices;
  final String? selectedDeviceSerial;

  const FileManagerScreen({
    Key? key,
    required this.connectedDevices,
    this.selectedDeviceSerial,
  }) : super(key: key);

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _currentPath = "/sdcard/Android/data";
  List<AdbFileEntry> _entries = [];
  bool _isLoading = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDirectory(_currentPath);
  }

  @override
  void didUpdateWidget(covariant FileManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDeviceSerial != widget.selectedDeviceSerial) {
      _loadDirectory(_currentPath);
    }
  }

  Future<void> _loadDirectory(String targetPath) async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null || serial.isEmpty) {
      setState(() {
        _entries = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _currentPath = targetPath;
    });

    final list = await AdbManager.listDirectory(serial, targetPath);
    if (mounted) {
      setState(() {
        _entries = list;
        _isLoading = false;
      });
    }
  }

  void _navigateToParent() {
    if (_currentPath == "/" || _currentPath.isEmpty) return;
    final normalized = _currentPath.endsWith('/') ? _currentPath.substring(0, _currentPath.length - 1) : _currentPath;
    final lastSlashIndex = normalized.lastIndexOf('/');
    if (lastSlashIndex <= 0) {
      _loadDirectory("/");
    } else {
      _loadDirectory(normalized.substring(0, lastSlashIndex));
    }
  }

  Future<void> _handleBackupSingleApp(String packageName) async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null) return;

    final targetDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select PC Folder to Save App Data Backup',
    );
    if (targetDir == null || targetDir.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📦 Backing up app data for $packageName...'), duration: const Duration(seconds: 2)),
    );

    final res = await AdbManager.backupAppData(serial, packageName, targetDir);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Backup finished')),
      );
    }
  }

  Future<void> _handleBatchBackupModal() async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null) return;

    // Scan /sdcard/Android/data for app data folders
    final appFolders = await AdbManager.listDirectory(serial, "/sdcard/Android/data");
    final selectedPkgs = <String>{};
    for (var f in appFolders) {
      if (f.isDirectory) selectedPkgs.add(f.name);
    }

    if (selectedPkgs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app data folders found in /sdcard/Android/data/')),
        );
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF181818),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2D2D2D))),
            title: const Row(
              children: [
                Icon(Icons.inventory_2, color: Color(0xFF00FF66)),
                SizedBox(width: 10),
                Text('BATCH BACKUP APP DATA (/sdcard/Android/data/)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 580,
              height: 400,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Found ${appFolders.where((f) => f.isDirectory).length} App Data Folders', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setDialogState(() => selectedPkgs.addAll(appFolders.where((f) => f.isDirectory).map((f) => f.name))),
                            child: const Text('Select All', style: TextStyle(color: Color(0xFF00FF66), fontSize: 11)),
                          ),
                          TextButton(
                            onPressed: () => setDialogState(() => selectedPkgs.clear()),
                            child: const Text('Deselect All', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: appFolders.where((f) => f.isDirectory).length,
                      itemBuilder: (context, index) {
                        final folder = appFolders.where((f) => f.isDirectory).toList()[index];
                        final isChecked = selectedPkgs.contains(folder.name);
                        return CheckboxListTile(
                          activeColor: const Color(0xFF00FF66),
                          checkColor: Colors.black,
                          value: isChecked,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedPkgs.add(folder.name);
                              } else {
                                selectedPkgs.remove(folder.name);
                              }
                            });
                          },
                          secondary: FutureBuilder<List<int>?>(
                            future: AdbManager.getCachedPlayStoreIconBytes(folder.name),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    Uint8List.fromList(snapshot.data!),
                                    width: 30,
                                    height: 30,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, stack) => const Icon(Icons.folder, color: Color(0xFFFFB74D)),
                                  ),
                                );
                              }
                              return const Icon(Icons.folder, color: Color(0xFFFFB74D));
                            },
                          ),
                          title: Text(folder.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
                onPressed: selectedPkgs.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        final targetDir = await FilePicker.platform.getDirectoryPath(
                          dialogTitle: 'Select PC Destination Folder for Batch App Data Backup',
                        );
                        if (targetDir == null || targetDir.isEmpty) return;

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('📦 Starting batch backup of ${selectedPkgs.length} apps...')),
                          );
                        }

                        int successCount = 0;
                        for (final pkg in selectedPkgs) {
                          final res = await AdbManager.backupAppData(serial, pkg, targetDir);
                          if (res['success'] == true) successCount++;
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('🟢 Batch Backup Complete! $successCount / ${selectedPkgs.length} app data folders backed up to $targetDir')),
                          );
                        }
                      },
                icon: const Icon(Icons.download, size: 16),
                label: Text('BACKUP ${selectedPkgs.length} APPS', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleRestoreAppModal() async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null) return;

    final backupFolder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Local App Data Backup Folder to Restore (e.g. com.spotify.music)',
    );
    if (backupFolder == null || backupFolder.isEmpty) return;

    final folderName = Directory(backupFolder).path.split(RegExp(r'[/\\]')).last;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2D2D2D))),
        title: const Row(
          children: [
            Icon(Icons.restore, color: Color(0xFF00FF66)),
            SizedBox(width: 10),
            Text('RESTORE APP DATA BACKUP', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Source Backup Folder: $backupFolder', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
            const SizedBox(height: 8),
            Text('Target Package: $folderName', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('This will overwrite files in /sdcard/Android/data/$folderName with the backup contents. Proceed?', style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('🔄 Restoring $folderName app data...')),
              );
              final res = await AdbManager.restoreAppData(serial, folderName, backupFolder);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(res['message'] ?? 'Restore finished')),
                );
                _loadDirectory(_currentPath);
              }
            },
            icon: const Icon(Icons.upload, size: 16),
            label: const Text('RESTORE DATA', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePushFile() async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null) return;

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.paths.isEmpty) return;

    int count = 0;
    for (final path in result.paths) {
      if (path != null) {
        final success = await AdbManager.pushFileToPhone(serial, path, _currentPath);
        if (success) count++;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🟢 Uploaded $count / ${result.paths.length} files to $_currentPath!')),
      );
      _loadDirectory(_currentPath);
    }
  }

  Widget _buildBreadcrumbBar() {
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF121212),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            onPressed: _currentPath == "/" ? null : _navigateToParent,
            tooltip: 'Go to parent folder',
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _loadDirectory("/"),
            child: const Text('root / ', style: TextStyle(color: Color(0xFF00FF66), fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: parts.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final part = entry.value;
                  final pathUpToHere = "/" + parts.sublist(0, idx + 1).join('/');
                  final isLast = idx == parts.length - 1;
                  return Row(
                    children: [
                      InkWell(
                        onTap: () => _loadDirectory(pathUpToHere),
                        child: Text(
                          part,
                          style: TextStyle(
                            color: isLast ? Colors.white : const Color(0xFF9CA3AF),
                            fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (!isLast) const Text(' / ', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
            onPressed: () => _loadDirectory(_currentPath),
            tooltip: 'Refresh directory',
          ),
        ],
      ),
    );
  }

  Widget _buildFileItemIcon(AdbFileEntry entry) {
    if (entry.isDirectory) {
      // Check if folder name looks like an Android package name (e.g. com.spotify.music)
      if (entry.name.contains('.')) {
        return FutureBuilder<List<int>?>(
          future: AdbManager.getCachedPlayStoreIconBytes(entry.name),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  Uint8List.fromList(snapshot.data!),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => const Icon(Icons.folder, color: Color(0xFFFFB74D), size: 30),
                ),
              );
            }
            return const Icon(Icons.folder, color: Color(0xFFFFB74D), size: 30);
          },
        );
      }
      return const Icon(Icons.folder, color: Color(0xFFFFB74D), size: 30);
    }

    final ext = entry.name.contains('.') ? entry.name.split('.').last.toLowerCase() : '';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return const Icon(Icons.image, color: Color(0xFF4FC3F7), size: 28);
    } else if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
      return const Icon(Icons.video_library, color: Color(0xFFFF8A65), size: 28);
    } else if (['mp3', 'flac', 'wav', 'ogg', 'm4a'].contains(ext)) {
      return const Icon(Icons.audiotrack, color: Color(0xFFAED581), size: 28);
    } else if (['apk', 'xapk', 'apks'].contains(ext)) {
      return const Icon(Icons.android, color: Color(0xFF00FF66), size: 28);
    } else if (['zip', 'tar', 'gz', '7z', 'rar', 'obb'].contains(ext)) {
      return const Icon(Icons.archive, color: Color(0xFFCE93D8), size: 28);
    } else if (['db', 'sqlite'].contains(ext)) {
      return const Icon(Icons.storage, color: Color(0xFFFFD54F), size: 28);
    }
    return const Icon(Icons.insert_drive_file, color: Colors.grey, size: 28);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);

    final filtered = _entries.where((e) {
      final q = _searchQuery.toLowerCase();
      return e.name.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // 1. Top Action Toolbar (Backup, Restore, Push, Pull)
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF181818),
          child: Column(
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF66),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onPressed: serial == null ? null : _handleBatchBackupModal,
                    icon: const Icon(Icons.inventory_2, size: 16),
                    label: const Text('📦 BATCH BACKUP APP DATA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF242424),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onPressed: serial == null ? null : _handleRestoreAppModal,
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('🔄 RESTORE APP DATA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF242424),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: serial == null ? null : _handlePushFile,
                    icon: const Icon(Icons.upload_file, size: 14),
                    label: const Text('⬆️ UPLOAD FILE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Search input
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Filter files or package folders...',
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white, size: 18),
                  filled: true,
                  fillColor: const Color(0xFF0D0D0D),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D2D2D))),
                ),
              ),
            ],
          ),
        ),

        // 2. Breadcrumb Navigation Bar
        _buildBreadcrumbBar(),

        // 3. File Explorer Viewport
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF66)))
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        serial == null ? "Please connect an Android device" : "No files or folders found in this directory",
                        style: const TextStyle(color: Color(0xFF708090), fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, idx) {
                        final entry = filtered[idx];
                        return Card(
                          color: const Color(0xFF181818),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFF2D2D2D)),
                          ),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                              leading: _buildFileItemIcon(entry),
                              title: Text(
                                entry.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              subtitle: Text(
                                "${entry.formattedSize} | Modified: ${entry.modifiedDate}",
                                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                              ),
                              onTap: () {
                                if (entry.isDirectory) {
                                  _loadDirectory(entry.path);
                                }
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (entry.isDirectory && _currentPath.contains("Android/data"))
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00FF66),
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: () => _handleBackupSingleApp(entry.name),
                                      icon: const Icon(Icons.download, size: 14),
                                      label: const Text('Backup App Data', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(Icons.download_for_offline, color: Colors.white, size: 20),
                                    tooltip: 'Download / Pull to PC',
                                    onPressed: () async {
                                      final targetDir = await FilePicker.platform.getDirectoryPath(
                                        dialogTitle: 'Select PC Folder to Download ${entry.name}',
                                      );
                                      if (targetDir != null && targetDir.isNotEmpty) {
                                        final success = await AdbManager.pullFileFromPhone(serial!, entry.path, targetDir);
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(success ? "🟢 Downloaded ${entry.name} to $targetDir!" : "🔴 Download failed")),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Color(0xFFFF5252), size: 20),
                                    tooltip: 'Delete File / Folder',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogCtx) => AlertDialog(
                                          backgroundColor: const Color(0xFF181818),
                                          title: const Text('Delete Item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          content: Text('Delete ${entry.name} permanently from phone?', style: const TextStyle(color: Color(0xFF9CA3AF))),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
                                              onPressed: () => Navigator.pop(dialogCtx, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        final success = await AdbManager.deleteRemotePath(serial!, entry.path);
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(success ? "🟢 Deleted ${entry.name}" : "🔴 Delete failed")),
                                          );
                                          _loadDirectory(_currentPath);
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
