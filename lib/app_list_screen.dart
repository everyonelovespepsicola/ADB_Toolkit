import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'adb_manager.dart';

class AppListScreen extends StatefulWidget {
  final List<DeviceInfo> connectedDevices;
  final String? selectedDeviceSerial;

  const AppListScreen({
    Key? key,
    required this.connectedDevices,
    this.selectedDeviceSerial,
  }) : super(key: key);

  @override
  State<AppListScreen> createState() => _AppListScreenState();
}

class _AppListScreenState extends State<AppListScreen> {
  String _selectedTab = 'user'; // 'user', 'system', 'disabled'
  List<AppPackageInfo> _packages = [];
  bool _isLoading = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  @override
  void didUpdateWidget(covariant AppListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDeviceSerial != widget.selectedDeviceSerial) {
      _loadPackages();
    }
  }

  Future<void> _loadPackages() async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null || serial.isEmpty) {
      setState(() => _packages = []);
      return;
    }

    setState(() => _isLoading = true);
    final list = await AdbManager.listPackages(serial, filter: _selectedTab);
    if (mounted) {
      setState(() {
        _packages = list;
        _isLoading = false;
      });
    }
  }

  bool _isCriticalApp(String packageName) {
    final pkg = packageName.toLowerCase();
    final criticalList = [
      'com.android.systemui',
      'android',
      'com.google.android.gms',
      'com.android.phone',
      'com.android.settings',
      'com.android.keyguard',
      'com.android.providers.telephony',
      'com.motorola.launcher3',
      'com.google.android.apps.nexuslauncher',
      'com.sec.android.app.launcher',
      'com.miui.home',
      'com.huawei.android.launcher',
      'com.oppo.launcher',
      'com.android.launcher3',
    ];
    return criticalList.any((c) => pkg == c || pkg.contains('launcher') || pkg.contains('systemui'));
  }

  Future<void> _confirmAction({
    required String title,
    required String content,
    required Future<bool> Function() onConfirm,
    bool isWarning = false,
  }) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141824),
        title: Row(
          children: [
            if (isWarning) const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 24),
            if (isWarning) const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: isWarning ? const Color(0xFFFF5252) : Colors.white, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(content, style: const TextStyle(color: Color(0xFFB0C0D0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isWarning ? const Color(0xFFFF5252) : const Color(0xFFD32F2F)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await onConfirm();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? "🟢 Action completed!" : "🔴 Action failed!")),
                );
                _loadPackages();
              }
            },
            child: Text(isWarning ? 'Proceed & Freeze' : 'Confirm'),
          ),
        ],
      ),
    );
  }

  String _sortBy = 'date_desc'; // 'date_desc', 'date_asc', 'name_asc', 'name_desc'

  @override
  Widget build(BuildContext context) {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);

    final filtered = _packages.where((p) {
      final q = _searchQuery.toLowerCase();
      return p.packageName.toLowerCase().contains(q) || p.appName.toLowerCase().contains(q);
    }).toList();

    filtered.sort((a, b) {
      if (_sortBy == 'name_asc') {
        return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      } else if (_sortBy == 'name_desc') {
        return b.appName.toLowerCase().compareTo(a.appName.toLowerCase());
      } else if (_sortBy == 'date_desc') {
        return b.installTimestamp.compareTo(a.installTimestamp);
      } else if (_sortBy == 'date_asc') {
        return a.installTimestamp.compareTo(b.installTimestamp);
      }
      return 0;
    });

    return Column(
      children: [
        // Controls Header (Tabs & Search Bar & Sort Dropdown)
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF10131B),
          child: Column(
            children: [
              Row(
                children: [
                  _buildTabButton("User Apps", "user", Colors.white),
                  const SizedBox(width: 8),
                  _buildTabButton("System Apps", "system", const Color(0xFFFFB74D)),
                  const SizedBox(width: 8),
                  _buildTabButton("Disabled / Frozen", "disabled", const Color(0xFFBD93F9)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: _loadPackages,
                    tooltip: 'Refresh Package List',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search packages (e.g. facebook, chrome)...',
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        prefixIcon: const Icon(Icons.search, color: Colors.white),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = "");
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF121622),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF1F2636))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Sort Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121622),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF1F2636)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sort, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        DropdownButton<String>(
                          value: _sortBy,
                          underline: const SizedBox(),
                          dropdownColor: const Color(0xFF121622),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 'date_desc', child: Text('📅 Installed (Newest First)')),
                            DropdownMenuItem(value: 'date_asc', child: Text('📅 Installed (Oldest First)')),
                            DropdownMenuItem(value: 'name_asc', child: Text('🔤 Name (A - Z)')),
                            DropdownMenuItem(value: 'name_desc', child: Text('🔤 Name (Z - A)')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _sortBy = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Packages Count Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF141824),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Device: ${serial ?? 'None Selected'} | Total Packages: ${filtered.length}",
                style: const TextStyle(color: Color(0xFF8090A0), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // Package List Viewport
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DEAEA)))
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        serial == null ? "Please connect an Android device to view packages" : "No packages found in this view",
                        style: const TextStyle(color: Color(0xFF708090), fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, idx) {
                        final pkg = filtered[idx];
                        return Card(
                          color: const Color(0xFF121622),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF1F2636)),
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    FutureBuilder<List<int>?>(
                                      future: AdbManager.getCachedPlayStoreIconBytes(pkg.packageName),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData && snapshot.data != null) {
                                          return ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.memory(
                                              Uint8List.fromList(snapshot.data!),
                                              width: 36,
                                              height: 36,
                                              fit: BoxFit.cover,
                                              errorBuilder: (ctx, err, stack) => _buildFallbackIcon(pkg),
                                            ),
                                          );
                                        }
                                        return _buildFallbackIcon(pkg);
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  pkg.appName,
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                                ),
                                              ),
                                              if (_isCriticalApp(pkg.packageName))
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF3E1F00),
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: const Color(0xFFFFB74D)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 12),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'CRITICAL SYSTEM / LAUNCHER',
                                                        style: TextStyle(color: Color(0xFFFFB74D), fontSize: 9, fontWeight: FontWeight.bold),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          SelectableText(
                                            pkg.packageName,
                                            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  "Path: ${pkg.apkPath}",
                                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10),
                                ),
                                const SizedBox(height: 10),

                                // Action Buttons Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (pkg.isDisabled)
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: serial == null
                                            ? null
                                            : () => _confirmAction(
                                                  title: "Unfreeze / Enable App",
                                                  content: "Enable package ${pkg.packageName}?",
                                                  onConfirm: () => AdbManager.enablePackage(serial, pkg.packageName),
                                                ),
                                        icon: const Icon(Icons.wb_sunny, size: 14),
                                        label: const Text("Enable", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      )
                                    else
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _isCriticalApp(pkg.packageName) ? const Color(0xFFFFB74D) : Colors.white,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: serial == null
                                            ? null
                                            : () => _confirmAction(
                                                  title: _isCriticalApp(pkg.packageName) ? "⚠️ Freeze Core App / Launcher" : "Freeze / Disable App",
                                                  content: _isCriticalApp(pkg.packageName)
                                                      ? "⛔ WARNING: ${pkg.packageName} is a Home Screen Launcher or Core System Component.\n\nFreezing this app may remove your home screen icons or require unfreezing via the 'Disabled Apps' tab. Are you sure you want to freeze it?"
                                                      : "Disable package ${pkg.packageName} without root (pm disable-user)?",
                                                  isWarning: _isCriticalApp(pkg.packageName),
                                                  onConfirm: () => AdbManager.disablePackage(serial, pkg.packageName),
                                                ),
                                        icon: Icon(_isCriticalApp(pkg.packageName) ? Icons.warning : Icons.ac_unit, size: 14),
                                        label: const Text("Freeze", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1E2638),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: serial == null ? null : () => _showPermissionsModal(pkg),
                                      icon: const Icon(Icons.vpn_key, size: 14),
                                      label: const Text("Permissions", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 6),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1E2638),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: serial == null
                                          ? null
                                          : () => _confirmAction(
                                                title: "Clear Cache & Data",
                                                content: "Clear app data for ${pkg.packageName}?",
                                                onConfirm: () => AdbManager.clearPackageData(serial, pkg.packageName),
                                              ),
                                      icon: const Icon(Icons.cleaning_services, size: 14),
                                      label: const Text("Clear Data", style: TextStyle(fontSize: 11)),
                                    ),
                                    const SizedBox(width: 6),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFD32F2F),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: serial == null
                                          ? null
                                          : () => _confirmAction(
                                                title: "Uninstall Application",
                                                content: "Uninstall ${pkg.packageName}?",
                                                onConfirm: () => AdbManager.uninstallPackage(serial, pkg.packageName),
                                              ),
                                      icon: const Icon(Icons.delete, size: 14),
                                      label: const Text("Uninstall", style: TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  bool _isShowingPermissionsModal = false;

  void _showPermissionsModal(AppPackageInfo pkg) {
    if (_isShowingPermissionsModal) return;
    _isShowingPermissionsModal = true;

    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null) {
      _isShowingPermissionsModal = false;
      return;
    }

    final permCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121622),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF1F2636))),
        title: Row(
          children: [
            const Icon(Icons.vpn_key, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('GRANT / REVOKE ELEVATED PERMISSIONS', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(pkg.packageName, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ONE-CLICK POWER-USER PRESETS:', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPermPresetChip(ctx, serial, pkg.packageName, 'WRITE_SECURE_SETTINGS', 'android.permission.WRITE_SECURE_SETTINGS'),
                  _buildPermPresetChip(ctx, serial, pkg.packageName, 'BATTERY_STATS', 'android.permission.BATTERY_STATS'),
                  _buildPermPresetChip(ctx, serial, pkg.packageName, 'PACKAGE_USAGE_STATS', 'android.permission.PACKAGE_USAGE_STATS'),
                  _buildPermPresetChip(ctx, serial, pkg.packageName, 'READ_LOGS', 'android.permission.READ_LOGS'),
                  _buildPermPresetChip(ctx, serial, pkg.packageName, 'DUMP', 'android.permission.DUMP'),
                  _buildPermPresetChip(ctx, serial, pkg.packageName, 'SYSTEM_ALERT_WINDOW', 'android.permission.SYSTEM_ALERT_WINDOW'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('GRANT OR REVOKE ANY CUSTOM PERMISSION:', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: permCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'e.g. android.permission.CHANGE_CONFIGURATION',
                  hintStyle: TextStyle(color: Color(0xFF6B7280)),
                  filled: true,
                  fillColor: Color(0xFF0B0C10),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFF1F2636))),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2638), foregroundColor: Colors.white),
                    onPressed: () async {
                      final perm = permCtrl.text.trim();
                      if (perm.isNotEmpty) {
                        final res = await AdbManager.revokePermission(serial, pkg.packageName, perm);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Done')));
                        }
                      }
                    },
                    icon: const Icon(Icons.remove_circle_outline, size: 14),
                    label: const Text('REVOKE VIA ADB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                    onPressed: () async {
                      final perm = permCtrl.text.trim();
                      if (perm.isNotEmpty) {
                        final res = await AdbManager.grantPermission(serial, pkg.packageName, perm);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Done')));
                        }
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 14),
                    label: const Text('GRANT VIA ADB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    ).then((_) {
      _isShowingPermissionsModal = false;
    });
  }

  Widget _buildPermPresetChip(BuildContext ctx, String serial, String pkg, String label, String fullPerm) {
    return ActionChip(
      backgroundColor: const Color(0xFF1E2638),
      side: const BorderSide(color: Color(0xFF2A3448)),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      onPressed: () async {
        final res = await AdbManager.grantPermission(serial, pkg, fullPerm);
        if (mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text(res['success'] == true ? "🟢 Granted $label to $pkg!" : "🔴 ${res['message']}")),
          );
        }
      },
    );
  }

  Widget _buildTabButton(String label, String key, Color color) {
    final isSelected = _selectedTab == key;
    return InkWell(
      onTap: () {
        setState(() => _selectedTab = key);
        _loadPackages();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF1E2638),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? Colors.white : const Color(0xFF2A3448)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : const Color(0xFF9CA3AF),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackIcon(AppPackageInfo pkg) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: pkg.isDisabled ? const Color(0xFF4A148C) : const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        pkg.isDisabled ? Icons.ac_unit : (pkg.isSystem ? Icons.settings : Icons.android),
        color: Colors.white,
        size: 20,
      ),
    );
  }
}
