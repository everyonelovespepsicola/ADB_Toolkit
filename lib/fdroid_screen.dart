import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'adb_manager.dart';

class FDroidApp {
  final String name;
  final String packageName;
  final String summary;
  final String description;
  final String license;
  final String author;
  final List<String> categories;
  final String iconUrl;
  final String apkUrl;
  final String version;

  FDroidApp({
    required this.name,
    required this.packageName,
    required this.summary,
    required this.description,
    required this.license,
    required this.author,
    required this.categories,
    required this.iconUrl,
    required this.apkUrl,
    required this.version,
  });

  String get mainCategory => categories.isNotEmpty ? categories.first : "System";
}

class FDroidScreen extends StatefulWidget {
  final List<DeviceInfo> connectedDevices;
  final String? selectedDeviceSerial;

  const FDroidScreen({
    Key? key,
    required this.connectedDevices,
    this.selectedDeviceSerial,
  }) : super(key: key);

  @override
  State<FDroidScreen> createState() => _FDroidScreenState();
}

class _FDroidScreenState extends State<FDroidScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  String _viewMode = 'column'; // 'column' (list view default) or 'grid'
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _installingApps = {}; // pkg -> status log
  Set<String> _installedPackageNames = {};
  bool _isSyncingRepo = false;
  String _syncStatus = "";

  @override
  void initState() {
    super.initState();
    _loadInstalledPackages();
  }

  @override
  void didUpdateWidget(covariant FDroidScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDeviceSerial != widget.selectedDeviceSerial) {
      _loadInstalledPackages();
    }
  }

  Future<void> _loadInstalledPackages() async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null || serial.isEmpty) {
      if (mounted) setState(() => _installedPackageNames = {});
      return;
    }

    try {
      final list = await AdbManager.listPackages(serial, filter: 'all');
      if (mounted) {
        setState(() {
          _installedPackageNames = list.map((p) => p.packageName).toSet();
        });
      }
    } catch (_) {}
  }

  final List<String> _repoMirrors = [
    "https://f-droid.org/repo",
    "https://ftp.fau.de/fdroid/repo",
    "https://mirror.fcix.net/fdroid/repo",
    "https://ftp.gwdg.de/pub/android/fdroid/repo",
  ];

  Future<void> _syncFDroidRepo() async {
    setState(() {
      _isSyncingRepo = true;
      _syncStatus = "Syncing official F-Droid repository index...";
    });

    http.Response? res;
    String activeBaseUrl = _repoMirrors.first;

    for (final mirror in _repoMirrors) {
      try {
        setState(() => _syncStatus = "Connecting to ${Uri.parse(mirror).host}...");
        final response = await http.get(
          Uri.parse("$mirror/index-v1.json"),
          headers: {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          res = response;
          activeBaseUrl = mirror;
          break;
        }
      } catch (_) {}
    }

    try {
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final appsData = data['apps'] as List<dynamic>?;
        final pkgsData = data['packages'] as Map<String, dynamic>?;

        if (appsData != null && pkgsData != null) {
          final List<FDroidApp> liveApps = [];
          for (final a in appsData) {
            final pkg = a['packageName'] as String?;
            if (pkg == null || pkg.isEmpty) continue;

            String name = a['name'] as String? ?? '';
            if (name.isEmpty && a['localized'] != null && a['localized']['en-US'] != null) {
              name = a['localized']['en-US']['name'] as String? ?? '';
            }
            if (name.isEmpty) {
              final parts = pkg.split('.');
              final raw = parts.last;
              name = raw.isNotEmpty ? (raw[0].toUpperCase() + raw.substring(1)) : pkg;
            }

            final summary = a['summary'] as String? ?? '';
            final description = a['description'] as String? ?? summary;
            final license = a['license'] as String? ?? 'Open Source';
            final author = a['authorName'] as String? ?? a['authorEmail'] as String? ?? 'F-Droid Contributor';
            String icon = a['icon'] as String? ?? '';
            if (icon.isEmpty && a['localized'] != null && a['localized']['en-US'] != null) {
              icon = a['localized']['en-US']['icon'] as String? ?? '';
            }

            String fullIconUrl = '';
            if (icon.isNotEmpty) {
              if (icon.startsWith('http://') || icon.startsWith('https://')) {
                fullIconUrl = icon;
              } else if (icon.contains('/')) {
                fullIconUrl = "$activeBaseUrl/$icon";
              } else {
                // F-Droid official mirror icon directory
                fullIconUrl = "$activeBaseUrl/icons-640/$icon";
              }
            }

            final catList = (a['categories'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? ['System'];

            if (pkgsData.containsKey(pkg)) {
              final pkgInfoList = pkgsData[pkg] as List<dynamic>?;
              if (pkgInfoList != null && pkgInfoList.isNotEmpty) {
                final pkgInfo = pkgInfoList.first;
                final apkName = pkgInfo['apkName'] as String?;
                final verName = pkgInfo['versionName'] as String? ?? 'v1.0';

                if (apkName != null) {
                  liveApps.add(
                    FDroidApp(
                      name: name,
                      packageName: pkg,
                      summary: summary,
                      description: description,
                      license: license,
                      author: author,
                      categories: catList,
                      iconUrl: fullIconUrl,
                      apkUrl: "$activeBaseUrl/$apkName",
                      version: verName.startsWith('v') ? verName : "v$verName",
                    ),
                  );
                }
              }
            }
          }

          if (liveApps.isNotEmpty && mounted) {
            setState(() {
              _popularFDroidApps.clear();
              _popularFDroidApps.addAll(liveApps);
              _syncStatus = "🟢 Synced ${liveApps.length} live apps via ${Uri.parse(activeBaseUrl).host}!";
            });
          }
        }
      } else {
        throw "Failed to connect to F-Droid mirrors";
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = "⚠️ Mirror sync fallback active.";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingRepo = false);
      }
    }
  }

  final List<String> _categories = [
    'All',
    'Installed',
    'Games',
    'Multimedia',
    'Internet',
    'System',
    'Security',
    'Development',
    'Graphics',
    'Science & Education',
    'Time',
  ];

  final List<FDroidApp> _popularFDroidApps = [
    FDroidApp(
      name: 'Droidify',
      packageName: 'com.looker.droidify',
      summary: 'F-Droid client with Material You design and fast index sync',
      description: 'A modern F-Droid client designed with Material You guidelines, fast repository syncing, parallel downloads, and background updating.',
      license: 'GPL-3.0',
      author: 'Looker',
      categories: ['System'],
      iconUrl: 'https://f-droid.org/repo/com.looker.droidify/en-US/icon_1tL3X1fH1i_0hT2L2bF6Y9x_.png',
      apkUrl: 'https://f-droid.org/repo/com.looker.droidify_10400.apk',
      version: 'v0.5.8',
    ),
    FDroidApp(
      name: 'NewPipe',
      packageName: 'org.schabi.newpipe',
      summary: 'Lightweight YouTube frontend with background play & downloads',
      description: 'NewPipe is a lightweight media application for Android designed to provide a YouTube experience without proprietary Google APIs or tracking.',
      license: 'GPL-3.0',
      author: 'Schabi',
      categories: ['Multimedia'],
      iconUrl: 'https://f-droid.org/repo/org.schabi.newpipe/en-US/icon_u2bXF5h1B9c0_.png',
      apkUrl: 'https://f-droid.org/repo/org.schabi.newpipe_0.27.0.apk',
      version: 'v0.27.0',
    ),
    FDroidApp(
      name: 'Termux',
      packageName: 'com.termux',
      summary: 'Full Linux terminal emulator and Linux environment setup',
      description: 'Termux combines powerful terminal emulation with an extensive Linux package collection including Python, Rust, Node.js, Git, and OpenSSH.',
      license: 'GPL-3.0',
      author: 'Fredrik Fornwall',
      categories: ['Development', 'System'],
      iconUrl: 'https://f-droid.org/repo/com.termux/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/com.termux_118.apk',
      version: 'v0.118.0',
    ),
    FDroidApp(
      name: 'VLC for Android',
      packageName: 'org.videolan.vlc',
      summary: 'Open source media player playing all video & audio formats',
      description: 'VLC media player is a free and open source cross-platform multimedia player that plays most multimedia files as well as discs, devices, and network streaming protocols.',
      license: 'GPL-2.0',
      author: 'VideoLAN',
      categories: ['Multimedia'],
      iconUrl: 'https://f-droid.org/repo/org.videolan.vlc/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/org.videolan.vlc_3050400.apk',
      version: 'v3.5.4',
    ),
    FDroidApp(
      name: 'Mihon (Tachiyomi)',
      packageName: 'mihon.app',
      summary: 'Open source manga & webtoon reader with offline downloads',
      description: 'Mihon is a free open source manga reader for Android with configurable reading modes, offline downloading, categories, and tracking service support.',
      license: 'Apache-2.0',
      author: 'Mihon App Team',
      categories: ['Multimedia'],
      iconUrl: 'https://f-droid.org/repo/mihon.app/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/mihon.app_16.apk',
      version: 'v0.16.5',
    ),
    FDroidApp(
      name: 'Organic Maps',
      packageName: 'app.organicmaps',
      summary: 'Offline hiking and cycling privacy-focused GPS maps',
      description: 'Organic Maps is an open-source offline maps app for travelers, tourists, hikers, and cyclists based on crowd-sourced OpenStreetMap data.',
      license: 'Apache-2.0',
      author: 'Organic Maps Community',
      categories: ['Internet', 'Navigation'],
      iconUrl: 'https://f-droid.org/repo/app.organicmaps/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/app.organicmaps_24050104.apk',
      version: 'v2024.05.01',
    ),
  ];

  void _showAppDetailsModal(FDroidApp app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121622),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF1E283A))),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                app.iconUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(
                  width: 48,
                  height: 48,
                  color: const Color(0xFF1E3A5F),
                  child: const Icon(Icons.android, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  SelectableText(app.packageName, style: const TextStyle(color: Color(0xFF4DEAEA), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF1E283A), borderRadius: BorderRadius.circular(6)),
                      child: Text(app.version, style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF2A1C30), borderRadius: BorderRadius.circular(6)),
                      child: Text(app.license, style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF1C2234), borderRadius: BorderRadius.circular(6)),
                      child: Text(app.mainCategory, style: const TextStyle(color: Color(0xFF90A0B0), fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('SUMMARY', style: TextStyle(color: Color(0xFF506070), fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(app.summary, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                const Text('DESCRIPTION', style: TextStyle(color: Color(0xFF506070), fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(app.description.replaceAll(RegExp(r'<[^>]*>'), ''), style: const TextStyle(color: Color(0xFFB0C0D0), fontSize: 12, height: 1.4)),
                const SizedBox(height: 14),
                const Text('AUTHOR / DEVELOPER', style: TextStyle(color: Color(0xFF506070), fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(app.author, style: const TextStyle(color: Color(0xFF4DEAEA), fontSize: 12)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
          if (_installedPackageNames.contains(app.packageName))
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(ctx).pop();
                _uninstallFDroidApp(app);
              },
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('UNINSTALL FROM PHONE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
            onPressed: () {
              Navigator.of(ctx).pop();
              _installFDroidApp(app);
            },
            icon: const Icon(Icons.download, size: 16),
            label: Text(_installedPackageNames.contains(app.packageName) ? 'RE-INSTALL / UPDATE' : 'INSTALL TO PHONE', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _uninstallFDroidApp(FDroidApp app) async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null) return;

    setState(() => _installingApps[app.packageName] = "Uninstalling...");

    try {
      final success = await AdbManager.uninstallPackage(serial, app.packageName);
      if (mounted) {
        setState(() {
          _installingApps.remove(app.packageName);
        });
        if (success) {
          _loadInstalledPackages();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? "🟢 Uninstalled ${app.name} from $serial!" : "🔴 Failed to uninstall ${app.name}!",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _installingApps.remove(app.packageName));
      }
    }
  }

  Future<void> _installFDroidApp(FDroidApp app) async {
    final serial = widget.selectedDeviceSerial ?? (widget.connectedDevices.isNotEmpty ? widget.connectedDevices.first.serial : null);
    if (serial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ No Android device selected! Please connect a phone.')),
      );
      return;
    }

    setState(() => _installingApps[app.packageName] = "Downloading APK...");

    try {
      final tempDir = await getTemporaryDirectory();
      final targetApk = File("${tempDir.path}\\${app.packageName}_${app.version}.apk");

      final res = await http.get(Uri.parse(app.apkUrl));
      if (res.statusCode == 200) {
        await targetApk.writeAsBytes(res.bodyBytes);
        setState(() => _installingApps[app.packageName] = "Pushing via ADB to $serial...");

        final devList = widget.connectedDevices.where((d) => d.serial == serial).toList();
        final dev = devList.isNotEmpty ? devList.first : null;

        final result = await AdbManager.installApk(serial, targetApk.path, sdkVersion: dev?.sdkVersion);

        try { targetApk.deleteSync(); } catch (_) {}

        if (mounted) {
          setState(() {
            _installingApps.remove(app.packageName);
          });
          if (result['success'] == true) {
            _loadInstalledPackages();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['success'] == true
                    ? "🟢 ${app.name} installed successfully on ${dev?.displayName ?? serial}!"
                    : "🔴 Failed to install ${app.name}: ${result['message']}",
              ),
            ),
          );
        }
      } else {
        throw "HTTP ${res.statusCode} download error";
      }
    } catch (e) {
      if (mounted) {
        setState(() => _installingApps.remove(app.packageName));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("🔴 Error installing ${app.name}: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _popularFDroidApps.where((app) {
      final q = _searchQuery.toLowerCase();
      final matchesSearch = q.isEmpty || app.name.toLowerCase().contains(q) || app.packageName.toLowerCase().contains(q) || app.summary.toLowerCase().contains(q);

      if (!matchesSearch) return false;
      if (_selectedCategory == 'All') return true;
      if (_selectedCategory == 'Installed') {
        return _installedPackageNames.contains(app.packageName);
      }

      // Fuzzy case-insensitive category matching (Games, Multimedia, System, etc.)
      final selLower = _selectedCategory.toLowerCase();
      return app.categories.any((c) {
        final cLower = c.toLowerCase();
        if (selLower == 'games' || selLower == 'game') {
          return cLower == 'games' || cLower == 'game' || cLower.contains('game');
        }
        return cLower == selLower || cLower.contains(selLower) || selLower.contains(cLower);
      });
    }).toList();

    return Column(
      children: [
        // Header & Category Bar
        Container(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF10131B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'F-DROID OPEN-SOURCE APP STORE',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  if (_syncStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        _syncStatus,
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),

                  // View Mode Toggle (Grid vs List/Column)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: const Color(0xFF121622), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1F2636))),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.grid_view, size: 16, color: _viewMode == 'grid' ? Colors.white : Colors.grey),
                          onPressed: () => setState(() => _viewMode = 'grid'),
                          tooltip: 'Grid View',
                        ),
                        IconButton(
                          icon: Icon(Icons.view_list, size: 16, color: _viewMode == 'column' ? Colors.white : Colors.grey),
                          onPressed: () => setState(() => _viewMode = 'column'),
                          tooltip: 'Column / List View',
                        ),
                      ],
                    ),
                  ),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: _isSyncingRepo ? null : _syncFDroidRepo,
                    icon: _isSyncingRepo
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.refresh, size: 14),
                    label: Text(
                      _isSyncingRepo ? "SYNCING REPOS..." : "REFRESH REPOS",
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Search Bar
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search open-source apps (e.g. NewPipe, Droidify, Termux)...',
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF1F2636))),
                ),
              ),
              const SizedBox(height: 10),

              // Category Pills
              SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (ctx, idx) {
                    final cat = _categories[idx];
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ChoiceChip(
                        label: Text(cat, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        selected: isSelected,
                        selectedColor: Colors.white,
                        backgroundColor: const Color(0xFF121622),
                        onSelected: (val) => setState(() => _selectedCategory = cat),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // App Catalog Body (Grid or Column)
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching F-Droid apps found', style: TextStyle(color: Colors.grey)))
              : (_viewMode == 'grid' ? _buildGridView(filtered) : _buildColumnView(filtered)),
        ),
      ],
    );
  }

  Widget _buildGridView(List<FDroidApp> apps) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 140,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: apps.length,
      itemBuilder: (ctx, idx) {
        final app = apps[idx];
        final isInstalling = _installingApps.containsKey(app.packageName);
        final statusText = _installingApps[app.packageName];
        final isInstalled = _installedPackageNames.contains(app.packageName);

        return InkWell(
          onTap: () => _showAppDetailsModal(app),
          child: Card(
            color: const Color(0xFF121622),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isInstalled ? const Color(0xFF10B981) : const Color(0xFF1F2636), width: isInstalled ? 2 : 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: app.iconUrl.isNotEmpty
                        ? Image.network(
                            app.iconUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              width: 48,
                              height: 48,
                              color: const Color(0xFF1F2636),
                              child: const Icon(Icons.android, color: Colors.white),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: const Color(0xFF1F2636),
                            child: const Icon(Icons.android, color: Colors.white),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                app.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF1F2636), borderRadius: BorderRadius.circular(6)),
                              child: Text(app.version, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.summary,
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              app.mainCategory,
                              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isInstalled && !isInstalling)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: IconButton(
                                      icon: const Icon(Icons.delete_forever, color: Color(0xFFFF5252), size: 16),
                                      onPressed: () => _uninstallFDroidApp(app),
                                      tooltip: 'Uninstall ${app.name} from phone',
                                    ),
                                  ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isInstalling
                                        ? const Color(0xFFFFB74D)
                                        : (isInstalled ? const Color(0xFF064E3B) : Colors.white),
                                    foregroundColor: isInstalled ? const Color(0xFF34D399) : Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    side: isInstalled ? const BorderSide(color: Color(0xFF10B981)) : BorderSide.none,
                                  ),
                                  onPressed: isInstalling ? null : () => _installFDroidApp(app),
                                  icon: isInstalling
                                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                      : Icon(isInstalled ? Icons.check_circle : Icons.download, size: 14),
                                  label: Text(
                                    isInstalling
                                        ? (statusText ?? "INSTALLING...")
                                        : (isInstalled ? "INSTALLED" : "INSTALL TO PHONE"),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildColumnView(List<FDroidApp> apps) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: apps.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final app = apps[idx];
        final isInstalling = _installingApps.containsKey(app.packageName);
        final statusText = _installingApps[app.packageName];
        final isInstalled = _installedPackageNames.contains(app.packageName);

        return InkWell(
          onTap: () => _showAppDetailsModal(app),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF121622),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isInstalled ? const Color(0xFF10B981) : const Color(0xFF1F2636), width: isInstalled ? 2 : 1),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: app.iconUrl.isNotEmpty
                      ? Image.network(
                          app.iconUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(
                            width: 40,
                            height: 40,
                            color: const Color(0xFF1F2636),
                            child: const Icon(Icons.android, color: Colors.white, size: 20),
                          ),
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          color: const Color(0xFF1F2636),
                          child: const Icon(Icons.android, color: Colors.white, size: 20),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      SelectableText(app.packageName, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(app.summary, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF1F2636), borderRadius: BorderRadius.circular(6)),
                  child: Text(app.version, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                if (isInstalled && !isInstalling)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: IconButton(
                      icon: const Icon(Icons.delete_forever, color: Color(0xFFFF5252), size: 18),
                      onPressed: () => _uninstallFDroidApp(app),
                      tooltip: 'Uninstall ${app.name} from phone',
                    ),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isInstalling
                        ? const Color(0xFFFFB74D)
                        : (isInstalled ? const Color(0xFF064E3B) : Colors.white),
                    foregroundColor: isInstalled ? const Color(0xFF34D399) : Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    side: isInstalled ? const BorderSide(color: Color(0xFF10B981)) : BorderSide.none,
                  ),
                  onPressed: isInstalling ? null : () => _installFDroidApp(app),
                  icon: isInstalling
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Icon(isInstalled ? Icons.check_circle : Icons.download, size: 14),
                  label: Text(
                    isInstalling
                        ? (statusText ?? "INSTALLING...")
                        : (isInstalled ? "INSTALLED" : "INSTALL"),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
