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
  final String category;
  final String iconUrl;
  final String apkUrl;
  final String version;

  FDroidApp({
    required this.name,
    required this.packageName,
    required this.summary,
    required this.category,
    required this.iconUrl,
    required this.apkUrl,
    required this.version,
  });
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
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _installingApps = {}; // pkg -> status log
  bool _isSyncingRepo = false;
  String _syncStatus = "";

  Future<void> _syncFDroidRepo() async {
    setState(() {
      _isSyncingRepo = true;
      _syncStatus = "Syncing official F-Droid repository index (index-v1.json)...";
    });

    try {
      final res = await http.get(
        Uri.parse("https://f-droid.org/repo/index-v1.json"),
        headers: {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final appsData = data['apps'] as List<dynamic>?;
        final pkgsData = data['packages'] as Map<String, dynamic>?;

        if (appsData != null && pkgsData != null) {
          final List<FDroidApp> liveApps = [];
          for (final a in appsData.take(200)) {
            final pkg = a['packageName'] as String?;
            final name = a['name'] as String? ?? a['summary'] as String? ?? pkg ?? '';
            final summary = a['summary'] as String? ?? '';
            final icon = a['icon'] as String? ?? '';
            final catList = a['categories'] as List<dynamic>?;
            final cat = (catList != null && catList.isNotEmpty) ? catList.first as String : 'System';

            if (pkg != null && pkgsData.containsKey(pkg)) {
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
                      category: cat,
                      iconUrl: icon.isNotEmpty ? "https://f-droid.org/repo/$pkg/en-US/$icon" : "https://f-droid.org/repo/com.termux/en-US/icon.png",
                      apkUrl: "https://f-droid.org/repo/$apkName",
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
              _syncStatus = "🟢 Synced ${liveApps.length} live apps from F-Droid repo!";
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = "⚠️ Sync timeout. Loaded cached default repo catalog.";
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
    'Multimedia',
    'Internet',
    'System',
    'Security',
    'Development',
    'Games',
  ];

  final List<FDroidApp> _popularFDroidApps = [
    FDroidApp(
      name: 'Droidify',
      packageName: 'com.looker.droidify',
      summary: 'F-Droid client with Material You design and fast index sync',
      category: 'System',
      iconUrl: 'https://f-droid.org/repo/com.looker.droidify/en-US/icon_1tL3X1fH1i_0hT2L2bF6Y9x_.png',
      apkUrl: 'https://f-droid.org/repo/com.looker.droidify_10400.apk',
      version: 'v0.5.8',
    ),
    FDroidApp(
      name: 'NewPipe',
      packageName: 'org.schabi.newpipe',
      summary: 'Lightweight YouTube frontend with background play & downloads',
      category: 'Multimedia',
      iconUrl: 'https://f-droid.org/repo/org.schabi.newpipe/en-US/icon_u2bXF5h1B9c0_.png',
      apkUrl: 'https://f-droid.org/repo/org.schabi.newpipe_0.27.0.apk',
      version: 'v0.27.0',
    ),
    FDroidApp(
      name: 'Termux',
      packageName: 'com.termux',
      summary: 'Full Linux terminal emulator and Linux environment setup',
      category: 'Development',
      iconUrl: 'https://f-droid.org/repo/com.termux/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/com.termux_118.apk',
      version: 'v0.118.0',
    ),
    FDroidApp(
      name: 'VLC for Android',
      packageName: 'org.videolan.vlc',
      summary: 'Open source media player playing all video & audio formats',
      category: 'Multimedia',
      iconUrl: 'https://f-droid.org/repo/org.videolan.vlc/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/org.videolan.vlc_3050400.apk',
      version: 'v3.5.4',
    ),
    FDroidApp(
      name: 'Mihon (Tachiyomi)',
      packageName: 'mihon.app',
      summary: 'Open source manga & webtoon reader with offline downloads',
      category: 'Multimedia',
      iconUrl: 'https://f-droid.org/repo/mihon.app/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/mihon.app_16.apk',
      version: 'v0.16.5',
    ),
    FDroidApp(
      name: 'Organic Maps',
      packageName: 'app.organicmaps',
      summary: 'Offline hiking and cycling privacy-focused GPS maps',
      category: 'Internet',
      iconUrl: 'https://f-droid.org/repo/app.organicmaps/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/app.organicmaps_24050104.apk',
      version: 'v2024.05.01',
    ),
    FDroidApp(
      name: 'Signal',
      packageName: 'org.thoughtcrime.securesms',
      summary: 'Private encrypted messaging and voice calling app',
      category: 'Security',
      iconUrl: 'https://f-droid.org/repo/org.thoughtcrime.securesms/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/org.thoughtcrime.securesms_700.apk',
      version: 'v7.0.0',
    ),
    FDroidApp(
      name: 'F-Droid Basic',
      packageName: 'org.fdroid.fdroid.basic',
      summary: 'Official lightweight F-Droid app store client',
      category: 'System',
      iconUrl: 'https://f-droid.org/repo/org.fdroid.fdroid.basic/en-US/icon.png',
      apkUrl: 'https://f-droid.org/repo/org.fdroid.fdroid.basic_1019000.apk',
      version: 'v1.19.0',
    ),
  ];

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

      // Download APK from F-Droid Repo
      final res = await http.get(Uri.parse(app.apkUrl));
      if (res.statusCode == 200) {
        await targetApk.writeAsBytes(res.bodyBytes);
        setState(() => _installingApps[app.packageName] = "Pushing via ADB to $serial...");

        // Find connected device info to get sdkVersion
        final devList = widget.connectedDevices.where((d) => d.serial == serial).toList();
        final dev = devList.isNotEmpty ? devList.first : null;

        final result = await AdbManager.installApk(serial, targetApk.path, sdkVersion: dev?.sdkVersion);

        // Cleanup temp file
        try { targetApk.deleteSync(); } catch (_) {}

        if (mounted) {
          setState(() {
            _installingApps.remove(app.packageName);
          });
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
      final matchesCat = _selectedCategory == 'All' || app.category == _selectedCategory;
      final q = _searchQuery.toLowerCase();
      final matchesSearch = q.isEmpty || app.name.toLowerCase().contains(q) || app.packageName.toLowerCase().contains(q) || app.summary.toLowerCase().contains(q);
      return matchesCat && matchesSearch;
    }).toList();

    return Column(
      children: [
        // F-Droid Store Header & Category Filter Bar
        Container(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF10131B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront, color: Color(0xFF00FF66), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'F-DROID OPEN-SOURCE APP STORE',
                    style: TextStyle(color: Color(0xFF00FF66), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  if (_syncStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        _syncStatus,
                        style: const TextStyle(color: Color(0xFF4DEAEA), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E283A),
                      foregroundColor: const Color(0xFF00FF66),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: _isSyncingRepo ? null : _syncFDroidRepo,
                    icon: _isSyncingRepo
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FF66)))
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
                  hintStyle: const TextStyle(color: Color(0xFF506070)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF00FF66)),
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
                  fillColor: const Color(0xFF090B10),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
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
                        selectedColor: const Color(0xFF00FF66),
                        backgroundColor: const Color(0xFF161A26),
                        onSelected: (val) => setState(() => _selectedCategory = cat),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // App Catalog Grid
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching F-Droid apps found', style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 140,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final app = filtered[idx];
                    final isInstalling = _installingApps.containsKey(app.packageName);
                    final statusText = _installingApps[app.packageName];

                    return Card(
                      color: const Color(0xFF121622),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF1E2638)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon Image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
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
                            const SizedBox(width: 10),

                            // Details & Install Button
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
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E283A),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(app.version, style: const TextStyle(color: Color(0xFF00FF66), fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    app.summary,
                                    style: const TextStyle(color: Color(0xFF8090A0), fontSize: 11),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),

                                  // Action Row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        app.category,
                                        style: const TextStyle(color: Color(0xFF506070), fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isInstalling ? const Color(0xFFFFB74D) : const Color(0xFF00FF66),
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: isInstalling ? null : () => _installFDroidApp(app),
                                        icon: isInstalling
                                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                            : const Icon(Icons.download, size: 14),
                                        label: Text(
                                          isInstalling ? (statusText ?? "INSTALLING...") : "INSTALL TO PHONE",
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
}
