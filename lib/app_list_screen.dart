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

  Future<void> _confirmAction({
    required String title,
    required String content,
    required Future<bool> Function() onConfirm,
  }) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141824),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Color(0xFF90A0B0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);

    final filtered = _packages.where((p) {
      final q = _searchQuery.toLowerCase();
      return p.packageName.toLowerCase().contains(q) || p.appName.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Controls Header (Tabs & Search Bar)
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF10131C),
          child: Column(
            children: [
              Row(
                children: [
                  _buildTabButton("User Apps", "user", Colors.blue),
                  const SizedBox(width: 8),
                  _buildTabButton("System Apps", "system", Colors.orange),
                  const SizedBox(width: 8),
                  _buildTabButton("Disabled / Frozen", "disabled", Colors.purple),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF4DEAEA)),
                    onPressed: _loadPackages,
                    tooltip: 'Refresh Package List',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search packages (e.g. facebook, chrome)...',
                  hintStyle: const TextStyle(color: Color(0xFF506070)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF4DEAEA)),
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
                  fillColor: const Color(0xFF0A0C12),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
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
                          color: const Color(0xFF121520),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    FutureBuilder<List<int>?>(
                                      future: serial != null ? AdbManager.getAppIconBytes(serial, pkg.packageName, pkg.apkPath) : null,
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
                                          Text(
                                            pkg.appName,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          const SizedBox(height: 2),
                                          SelectableText(
                                            pkg.packageName,
                                            style: const TextStyle(color: Color(0xFF4DEAEA), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  "Path: ${pkg.apkPath}",
                                  style: const TextStyle(color: Color(0xFF607080), fontSize: 10),
                                ),
                                const SizedBox(height: 10),

                                // Action Buttons Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (pkg.isDisabled)
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF4CAF50),
                                          foregroundColor: Colors.white,
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
                                        label: const Text("Enable", style: TextStyle(fontSize: 11)),
                                      )
                                    else
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF9C27B0),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: serial == null
                                            ? null
                                            : () => _confirmAction(
                                                  title: "Freeze / Disable App",
                                                  content: "Disable package ${pkg.packageName} without root (pm disable-user)?",
                                                  onConfirm: () => AdbManager.disablePackage(serial, pkg.packageName),
                                                ),
                                        icon: const Icon(Icons.ac_unit, size: 14),
                                        label: const Text("Freeze", style: TextStyle(fontSize: 11)),
                                      ),
                                    const SizedBox(width: 6),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF333A4C),
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

  Widget _buildTabButton(String label, String key, Color color) {
    final isSelected = _selectedTab == key;
    return InkWell(
      onTap: () {
        setState(() => _selectedTab = key);
        _loadPackages();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : const Color(0xFF1A1D28),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
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
