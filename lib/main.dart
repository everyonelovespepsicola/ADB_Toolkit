import 'dart:async';
import 'package:flutter/material.dart';
import 'adb_manager.dart';
import 'dropzone_installer.dart';
import 'app_list_screen.dart';
import 'wifi_adb_screen.dart';

void main() {
  runApp(const AppManagerApp());
}

class AppManagerApp extends StatelessWidget {
  const AppManagerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android App Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFF4DEAEA),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4DEAEA),
          secondary: Color(0xFF2196F3),
          surface: Color(0xFF141824),
        ),
      ),
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
    final path = await AdbManager.getAdbExecutablePath();
    if (mounted) {
      setState(() {
        _adbPathStatus = path != null ? "Portable ADB Active: $path" : "Failed to resolve ADB";
      });
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
    final List<Widget> pages = [
      DropzoneInstaller(
        connectedDevices: _connectedDevices,
        selectedDeviceSerial: _selectedDeviceSerial,
      ),
      AppListScreen(
        connectedDevices: _connectedDevices,
        selectedDeviceSerial: _selectedDeviceSerial,
      ),
      WifiAdbScreen(
        connectedDevices: _connectedDevices,
        onDevicesUpdated: _refreshDevices,
      ),
      _buildSettingsView(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF10131B),
        elevation: 2,
        title: Row(
          children: [
            const Icon(Icons.phonelink_setup, color: Color(0xFF4DEAEA), size: 24),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Android App Manager',
                  style: TextStyle(color: Color(0xFF4DEAEA), fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  _adbPathStatus,
                  style: const TextStyle(color: Color(0xFF708090), fontSize: 10),
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
                  color: const Color(0xFF1C2234),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00FF66), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Color(0xFF00FF66), size: 10),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: _selectedDeviceSerial,
                      underline: const SizedBox(),
                      dropdownColor: const Color(0xFF1C2234),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                color: const Color(0xFF2A1C20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF5252), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Color(0xFFFF5252), size: 10),
                  SizedBox(width: 6),
                  Text('No Devices Connected', style: TextStyle(color: Color(0xFFFF5252), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        height: 56,
        decoration: const BoxDecoration(
          color: Color(0xFF0F1118),
          border: Border(top: BorderSide(color: Color(0xFF1A1F2C), width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildDockButton(
                label: '📥 INSTALLER',
                index: 0,
                activeColor: const Color(0xFF2196F3),
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '📱 APP MANAGER',
                index: 1,
                activeColor: const Color(0xFF4DEAEA),
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '📶 WI-FI ADB',
                index: 2,
                activeColor: const Color(0xFFFFB74D),
              ),
            ),
            Expanded(
              child: _buildDockButton(
                label: '⚙️ SETTINGS',
                index: 3,
                activeColor: const Color(0xFF9C27B0),
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
          color: isSelected ? activeColor : const Color(0xFF141722),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? (activeColor == const Color(0xFFFFB74D) ? Colors.black : Colors.white) : const Color(0xFF8090A0),
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
            style: TextStyle(color: Color(0xFF4DEAEA), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PORTABLE ADB BINARY PATH:', style: TextStyle(color: Color(0xFF8090A0), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(_adbPathStatus, style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), foregroundColor: Colors.white),
                  onPressed: _initAdb,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Re-resolve Local ADB'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ANDROID 15 INSTALLATION FLAGS:', style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  'All APK installations automatically execute with flags:\n  adb install -r -g --bypass-low-target-sdk-block <apk_path>\n\n-r: Replace existing app\n-g: Auto-grant all requested runtime permissions\n--bypass-low-target-sdk-block: Bypasses Android 14/15 legacy Target SDK blocks',
                  style: TextStyle(color: Color(0xFFB0C0D0), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
