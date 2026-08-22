import 'dart:convert';
import 'package:flutter/material.dart';
import 'adb_manager.dart';

enum SettingRiskLevel { critical, warning, safe }

class SettingRiskHelper {
  static const Set<String> _criticalKeys = {
    'adb_enabled',
    'development_settings_enabled',
    'device_provisioned',
    'user_setup_complete',
    'http_proxy',
    'global_http_proxy_host',
    'global_http_proxy_port',
    'install_non_market_apps',
    'package_verifier_enable',
    'adb_wifi_enabled',
    'secure_fbe_mode',
    'lock_screen_allow_private_notifications',
  };

  static const Set<String> _warningKeys = {
    'window_animation_scale',
    'transition_animation_scale',
    'animator_duration_scale',
    'private_dns_mode',
    'private_dns_specifier',
    'mobile_data',
    'wifi_on',
    'bluetooth_on',
    'stay_on_while_plugged_in',
    'screen_off_timeout',
    'zen_mode',
    'airplane_mode_on',
    'location_mode',
    'nfc_on',
    'screen_brightness',
    'accelerometer_rotation',
  };

  static SettingRiskLevel getRiskLevel(String key) {
    final k = key.toLowerCase();
    if (_criticalKeys.contains(k) || k.contains('adb_') || k.contains('provisioned') || k.contains('proxy')) {
      return SettingRiskLevel.critical;
    }
    if (_warningKeys.contains(k) || k.contains('dns') || k.contains('anim') || k.contains('timeout') || k.contains('mode')) {
      return SettingRiskLevel.warning;
    }
    return SettingRiskLevel.safe;
  }
}

class HiddenSettingsScreen extends StatefulWidget {
  final List<DeviceInfo> connectedDevices;
  final String? selectedDeviceSerial;

  const HiddenSettingsScreen({
    Key? key,
    required this.connectedDevices,
    this.selectedDeviceSerial,
  }) : super(key: key);

  @override
  State<HiddenSettingsScreen> createState() => _HiddenSettingsScreenState();
}

class _HiddenSettingsScreenState extends State<HiddenSettingsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const String _snapshotPath = '/sdcard/.app_manager_defaults.json';

  String _selectedNamespace = 'global'; // 'global', 'secure', 'system'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _quickTweaksScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _quickTweaksScrollController.dispose();
    super.dispose();
  }

  void _scrollQuickTweaks(double offset) {
    if (!_quickTweaksScrollController.hasClients || !_quickTweaksScrollController.position.hasContentDimensions) return;
    final target = (_quickTweaksScrollController.offset + offset).clamp(
      0.0,
      _quickTweaksScrollController.position.maxScrollExtent,
    );
    _quickTweaksScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
  final Map<String, Map<String, String>> _settingsCache = {
    'global': {},
    'secure': {},
    'system': {},
  };
  final Map<String, Map<String, String>> _defaultsCache = {
    'global': {},
    'secure': {},
    'system': {},
  };
  bool _isLoading = false;
  bool _hasPhoneSnapshot = false;

  // Quick Tweaks State
  double _animScale = 1.0;
  double _screenBrightness = 128.0;
  int _screenTimeoutMs = 60000;
  bool _stayAwake = false;
  bool _autoRotate = true;
  String _privateDnsHost = '';

  bool _showTouches = false;
  bool _pointerLocation = false;
  bool _highRefreshRate = false;
  bool _bypassHotspotDun = false;
  bool _disableVolumeWarning = false;
  bool _disableBannerToasts = false;
  bool _cleanDemoMode = false;
  bool _forceSplitScreen = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant HiddenSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDeviceSerial != widget.selectedDeviceSerial) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final serial = widget.selectedDeviceSerial;
    if (serial == null) {
      if (mounted) {
        setState(() {
          _settingsCache['global'] = {};
          _settingsCache['secure'] = {};
          _settingsCache['system'] = {};
          _defaultsCache['global'] = {};
          _defaultsCache['secure'] = {};
          _defaultsCache['system'] = {};
          _hasPhoneSnapshot = false;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);

    final results = await Future.wait([
      AdbManager.getSettingsList(serial, 'global'),
      AdbManager.getSettingsList(serial, 'secure'),
      AdbManager.getSettingsList(serial, 'system'),
      AdbManager.readPhoneFile(serial, _snapshotPath),
    ]);

    final globalSettings = results[0] as Map<String, String>;
    final secureSettings = results[1] as Map<String, String>;
    final systemSettings = results[2] as Map<String, String>;
    final snapshotJson = results[3] as String?;

    Map<String, String> defGlobal = {};
    Map<String, String> defSecure = {};
    Map<String, String> defSystem = {};
    bool hasSnapshot = false;

    if (snapshotJson != null && snapshotJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(snapshotJson) as Map<String, dynamic>;
        if (decoded.containsKey('global')) {
          defGlobal = Map<String, String>.from(decoded['global'] as Map);
        }
        if (decoded.containsKey('secure')) {
          defSecure = Map<String, String>.from(decoded['secure'] as Map);
        }
        if (decoded.containsKey('system')) {
          defSystem = Map<String, String>.from(decoded['system'] as Map);
        }
        hasSnapshot = true;
      } catch (_) {}
    }

    if (!hasSnapshot) {
      // Create initial baseline JSON snapshot on the phone
      defGlobal = Map<String, String>.from(globalSettings);
      defSecure = Map<String, String>.from(secureSettings);
      defSystem = Map<String, String>.from(systemSettings);

      // Populate default fallback keys for featured tweaks if missing
      defSystem['show_touches'] ??= '0';
      defSystem['pointer_location'] ??= '0';
      defSystem['peak_refresh_rate'] ??= '60.0';
      defGlobal['tether_dun_required'] ??= '1';
      defGlobal['audio_safe_volume_state'] ??= '2';
      defGlobal['heads_up_notifications_enabled'] ??= '1';
      defGlobal['sysui_demo_allowed'] ??= '0';
      defGlobal['force_resizable_activities'] ??= '0';

      final baselineMap = {
        'global': defGlobal,
        'secure': defSecure,
        'system': defSystem,
      };
      final jsonContent = const JsonEncoder.withIndent('  ').convert(baselineMap);
      await AdbManager.writePhoneFile(serial, _snapshotPath, jsonContent);
      hasSnapshot = true;
    }

    if (mounted) {
      setState(() {
        _settingsCache['global'] = globalSettings;
        _settingsCache['secure'] = secureSettings;
        _settingsCache['system'] = systemSettings;

        _defaultsCache['global'] = defGlobal;
        _defaultsCache['secure'] = defSecure;
        _defaultsCache['system'] = defSystem;
        _hasPhoneSnapshot = hasSnapshot;

        // Parse Quick Tweaks
        _animScale = double.tryParse(globalSettings['window_animation_scale'] ?? '1.0') ?? 1.0;
        _screenBrightness = double.tryParse(systemSettings['screen_brightness'] ?? '128') ?? 128.0;
        _screenTimeoutMs = int.tryParse(systemSettings['screen_off_timeout'] ?? '60000') ?? 60000;
        _stayAwake = (globalSettings['stay_on_while_plugged_in'] ?? '0') != '0';
        _autoRotate = (systemSettings['accelerometer_rotation'] ?? '1') == '1';
        _privateDnsHost = globalSettings['private_dns_specifier'] ?? '';

        _showTouches = (systemSettings['show_touches'] ?? '0') == '1';
        _pointerLocation = (systemSettings['pointer_location'] ?? '0') == '1';
        _highRefreshRate = (double.tryParse(systemSettings['peak_refresh_rate'] ?? '60.0') ?? 60.0) >= 90.0;
        _bypassHotspotDun = (globalSettings['tether_dun_required'] ?? '1') == '0';
        _disableVolumeWarning = (globalSettings['audio_safe_volume_state'] ?? '2') == '0';
        _disableBannerToasts = (globalSettings['heads_up_notifications_enabled'] ?? '1') == '0';
        _cleanDemoMode = (globalSettings['sysui_demo_allowed'] ?? '0') == '1';
        _forceSplitScreen = (globalSettings['force_resizable_activities'] ?? '0') == '1';

        _isLoading = false;
      });
    }
  }

  Future<void> _resetSettingToDefault(String namespace, String key) async {
    final defVal = _defaultsCache[namespace]?[key];
    if (defVal != null) {
      await _updateSetting(namespace, key, defVal);
    }
  }

  Future<void> _updateSetting(String namespace, String key, String value) async {
    final serial = widget.selectedDeviceSerial;
    if (serial == null) return;

    final risk = SettingRiskHelper.getRiskLevel(key);
    if (risk == SettingRiskLevel.critical) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1B0E14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFEF4444), width: 2),
          ),
          title: const Row(
            children: [
              Icon(Icons.report_problem, color: Color(0xFFEF4444), size: 24),
              SizedBox(width: 8),
              Text(
                'CRITICAL SETTING WARNING',
                style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are modifying "$key" in $namespace settings.',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                key == 'adb_enabled' && value == '0'
                    ? '⚠️ CRITICAL: Setting adb_enabled to 0 will immediately kill USB debugging on your Android device and disconnect App Manager!'
                    : '⚠️ WARNING: Modifying critical Android system flags can cause ADB disconnection, lock features, or system instability.',
                style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('CANCEL (SAFE)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('CONFIRM RISK & APPLY', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    final success = await AdbManager.putSetting(serial, namespace, key, value);
    if (mounted) {
      if (success) {
        setState(() {
          _settingsCache[namespace]?[key] = value;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🟢 Updated $key = $value in $namespace settings!'), duration: const Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🔴 Failed to update $key in $namespace settings.')),
        );
      }
    }
  }

  Future<void> _setAnimScale(double scale) async {
    setState(() => _animScale = scale);
    final valStr = scale.toStringAsFixed(1);
    await _updateSetting('global', 'window_animation_scale', valStr);
    await _updateSetting('global', 'transition_animation_scale', valStr);
    await _updateSetting('global', 'animator_duration_scale', valStr);
  }

  void _showAddSettingModal() {
    final keyCtrl = TextEditingController();
    final valCtrl = TextEditingController();
    String targetNamespace = _selectedNamespace;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121622),
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Text('ADD CUSTOM SYSTEM SETTING', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              value: targetNamespace,
              dropdownColor: const Color(0xFF121622),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: 'global', child: Text('GLOBAL Namespace')),
                DropdownMenuItem(value: 'secure', child: Text('SECURE Namespace')),
                DropdownMenuItem(value: 'system', child: Text('SYSTEM Namespace')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => targetNamespace = val);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: keyCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Setting Key (e.g. custom_flag_name)',
                labelStyle: TextStyle(color: Color(0xFF9CA3AF)),
                filled: true,
                fillColor: Color(0xFF0B0C10),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Setting Value (e.g. 1 or hostname)',
                labelStyle: TextStyle(color: Color(0xFF9CA3AF)),
                filled: true,
                fillColor: Color(0xFF0B0C10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted && Navigator.canPop(ctx)) {
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () {
              final k = keyCtrl.text.trim();
              final v = valCtrl.text.trim();
              if (k.isNotEmpty) {
                if (ctx.mounted && Navigator.canPop(ctx)) {
                  Navigator.of(ctx).pop();
                }
                _updateSetting(targetNamespace, k, v);
              }
            },
            child: const Text('ADD SETTING', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Map<String, String> tweaksMap = {
      'show_touches': _settingsCache['system']?['show_touches'] ?? '0',
      'pointer_location': _settingsCache['system']?['pointer_location'] ?? '0',
      'peak_refresh_rate': _settingsCache['system']?['peak_refresh_rate'] ?? '60.0',
      'tether_dun_required': _settingsCache['global']?['tether_dun_required'] ?? '1',
      'audio_safe_volume_state': _settingsCache['global']?['audio_safe_volume_state'] ?? '2',
      'heads_up_notifications_enabled': _settingsCache['global']?['heads_up_notifications_enabled'] ?? '1',
      'sysui_demo_allowed': _settingsCache['global']?['sysui_demo_allowed'] ?? '0',
      'force_resizable_activities': _settingsCache['global']?['force_resizable_activities'] ?? '0',
      'window_animation_scale': _settingsCache['global']?['window_animation_scale'] ?? '1.0',
      'screen_brightness': _settingsCache['system']?['screen_brightness'] ?? '128',
      'screen_off_timeout': _settingsCache['system']?['screen_off_timeout'] ?? '60000',
      'stay_on_while_plugged_in': _settingsCache['global']?['stay_on_while_plugged_in'] ?? '0',
      'accelerometer_rotation': _settingsCache['system']?['accelerometer_rotation'] ?? '1',
      'private_dns_specifier': _settingsCache['global']?['private_dns_specifier'] ?? '',
    };

    final currentMap = (_selectedNamespace == 'tweaks') ? tweaksMap : (_settingsCache[_selectedNamespace] ?? {});
    final defaultMap = _defaultsCache[_selectedNamespace] ?? {};

    final filteredEntries = currentMap.entries.where((e) {
      final q = _searchQuery.toLowerCase();
      return q.isEmpty || e.key.toLowerCase().contains(q) || e.value.toLowerCase().contains(q);
    }).toList();

    // Quick tweaks default checks
    final defAnimScale = double.tryParse(defaultMap['window_animation_scale'] ?? _defaultsCache['global']?['window_animation_scale'] ?? '1.0') ?? 1.0;
    final animModified = _animScale != defAnimScale;

    final defBrightness = double.tryParse(defaultMap['screen_brightness'] ?? _defaultsCache['system']?['screen_brightness'] ?? '128') ?? 128.0;
    final brightnessModified = _screenBrightness != defBrightness;

    final defTimeout = int.tryParse(defaultMap['screen_off_timeout'] ?? _defaultsCache['system']?['screen_off_timeout'] ?? '60000') ?? 60000;
    final timeoutModified = _screenTimeoutMs != defTimeout;

    final defStayAwake = ((defaultMap['stay_on_while_plugged_in'] ?? _defaultsCache['global']?['stay_on_while_plugged_in'] ?? '0') != '0');
    final stayAwakeModified = _stayAwake != defStayAwake;

    final defAutoRotate = ((defaultMap['accelerometer_rotation'] ?? _defaultsCache['system']?['accelerometer_rotation'] ?? '1') == '1');
    final autoRotateModified = _autoRotate != defAutoRotate;

    final defPrivateDns = defaultMap['private_dns_specifier'] ?? _defaultsCache['global']?['private_dns_specifier'] ?? '';
    final privateDnsModified = _privateDnsHost != defPrivateDns;

    final defTouches = (defaultMap['show_touches'] ?? _defaultsCache['system']?['show_touches'] ?? '0') == '1';
    final touchesModified = _showTouches != defTouches;

    final defPointer = (defaultMap['pointer_location'] ?? _defaultsCache['system']?['pointer_location'] ?? '0') == '1';
    final pointerModified = _pointerLocation != defPointer;

    final defRefresh = (double.tryParse(defaultMap['peak_refresh_rate'] ?? _defaultsCache['system']?['peak_refresh_rate'] ?? '60.0') ?? 60.0) >= 90.0;
    final refreshModified = _highRefreshRate != defRefresh;

    final defDun = (defaultMap['tether_dun_required'] ?? _defaultsCache['global']?['tether_dun_required'] ?? '1') == '0';
    final dunModified = _bypassHotspotDun != defDun;

    final defVolWarn = (defaultMap['audio_safe_volume_state'] ?? _defaultsCache['global']?['audio_safe_volume_state'] ?? '2') == '0';
    final volWarnModified = _disableVolumeWarning != defVolWarn;

    final defBanner = (defaultMap['heads_up_notifications_enabled'] ?? _defaultsCache['global']?['heads_up_notifications_enabled'] ?? '1') == '0';
    final bannerModified = _disableBannerToasts != defBanner;

    final defDemo = (defaultMap['sysui_demo_allowed'] ?? _defaultsCache['global']?['sysui_demo_allowed'] ?? '0') == '1';
    final demoModified = _cleanDemoMode != defDemo;

    final defSplit = (defaultMap['force_resizable_activities'] ?? _defaultsCache['global']?['force_resizable_activities'] ?? '0') == '1';
    final splitModified = _forceSplitScreen != defSplit;

    return Column(
      children: [
        // Top Section: Header & Featured System Quick Tweaks
        Container(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF10131B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'HIDDEN SETTINGS & FEATURED SYSTEM TWEAKS',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(width: 10),
                      if (_hasPhoneSnapshot)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF064E3B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sd_storage, color: Color(0xFF34D399), size: 12),
                              SizedBox(width: 4),
                              Text('PHONE SNAPSHOT ACTIVE', style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _loadSettings,
                        tooltip: 'Re-fetch Settings & Snapshot from Phone',
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                        onPressed: _showAddSettingModal,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('ADD CUSTOM KEY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Featured Quick Tweaks Row with Left/Right Track Scroll Controls
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
                    onPressed: () => _scrollQuickTweaks(-350),
                    tooltip: 'Scroll Track Left',
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _quickTweaksScrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // 🚀 Animation Scale Card
                          _buildQuickTweakCard(
                            title: '🚀 UI ANIMATION SCALE',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: animModified,
                            onReset: () => _setAnimScale(defAnimScale),
                            defaultHint: "${defAnimScale.toStringAsFixed(1)}x",
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("${_animScale.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 120,
                                  child: Slider(
                                    value: _animScale.clamp(0.0, 2.0),
                                    min: 0.0,
                                    max: 2.0,
                                    divisions: 4,
                                    activeColor: animModified ? const Color(0xFF10B981) : Colors.white,
                                    onChanged: (val) => _setAnimScale(val),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 👉 Show Touch Dots Card
                          _buildQuickTweakCard(
                            title: '👉 SHOW TOUCH DOTS',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: touchesModified,
                            onReset: () {
                              setState(() => _showTouches = defTouches);
                              _updateSetting('system', 'show_touches', defTouches ? '1' : '0');
                            },
                            defaultHint: defTouches ? 'On' : 'Off',
                            child: Switch(
                              value: _showTouches,
                              activeColor: touchesModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _showTouches = val);
                                _updateSetting('system', 'show_touches', val ? '1' : '0');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 🎯 Pointer Coordinates Card
                          _buildQuickTweakCard(
                            title: '🎯 POINTER COORDINATES',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: pointerModified,
                            onReset: () {
                              setState(() => _pointerLocation = defPointer);
                              _updateSetting('system', 'pointer_location', defPointer ? '1' : '0');
                            },
                            defaultHint: defPointer ? 'On' : 'Off',
                            child: Switch(
                              value: _pointerLocation,
                              activeColor: pointerModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _pointerLocation = val);
                                _updateSetting('system', 'pointer_location', val ? '1' : '0');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 🔥 Force High Refresh Rate (120Hz) Card
                          _buildQuickTweakCard(
                            title: '🔥 FORCE HIGH REFRESH (120Hz)',
                            riskLevel: SettingRiskLevel.warning,
                            isModified: refreshModified,
                            onReset: () {
                              setState(() => _highRefreshRate = defRefresh);
                              final valStr = defRefresh ? '120.0' : '60.0';
                              _updateSetting('system', 'peak_refresh_rate', valStr);
                              _updateSetting('system', 'min_refresh_rate', valStr);
                            },
                            defaultHint: defRefresh ? '120Hz' : '60Hz',
                            child: Switch(
                              value: _highRefreshRate,
                              activeColor: refreshModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _highRefreshRate = val);
                                final valStr = val ? '120.0' : '60.0';
                                _updateSetting('system', 'peak_refresh_rate', valStr);
                                _updateSetting('system', 'min_refresh_rate', valStr);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 📶 Bypass Hotspot DUN Cap Card
                          _buildQuickTweakCard(
                            title: '📶 BYPASS HOTSPOT DUN CAP',
                            riskLevel: SettingRiskLevel.warning,
                            isModified: dunModified,
                            onReset: () {
                              setState(() => _bypassHotspotDun = defDun);
                              _updateSetting('global', 'tether_dun_required', defDun ? '0' : '1');
                            },
                            defaultHint: defDun ? 'Active' : 'Off',
                            child: Switch(
                              value: _bypassHotspotDun,
                              activeColor: dunModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _bypassHotspotDun = val);
                                _updateSetting('global', 'tether_dun_required', val ? '0' : '1');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 🔊 Disable Safe Volume Warning Card
                          _buildQuickTweakCard(
                            title: '🔊 DISABLE VOLUME WARNING',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: volWarnModified,
                            onReset: () {
                              setState(() => _disableVolumeWarning = defVolWarn);
                              _updateSetting('global', 'audio_safe_volume_state', defVolWarn ? '0' : '2');
                            },
                            defaultHint: defVolWarn ? 'Disabled' : 'Enabled',
                            child: Switch(
                              value: _disableVolumeWarning,
                              activeColor: volWarnModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _disableVolumeWarning = val);
                                _updateSetting('global', 'audio_safe_volume_state', val ? '0' : '2');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 🔕 Disable Banner Toast Popups Card
                          _buildQuickTweakCard(
                            title: '🔕 DISABLE BANNER TOASTS',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: bannerModified,
                            onReset: () {
                              setState(() => _disableBannerToasts = defBanner);
                              _updateSetting('global', 'heads_up_notifications_enabled', defBanner ? '0' : '1');
                            },
                            defaultHint: defBanner ? 'Disabled' : 'Enabled',
                            child: Switch(
                              value: _disableBannerToasts,
                              activeColor: bannerModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _disableBannerToasts = val);
                                _updateSetting('global', 'heads_up_notifications_enabled', val ? '0' : '1');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 📸 Clean Screenshot Demo Mode Card
                          _buildQuickTweakCard(
                            title: '📸 CLEAN SCREENSHOT MODE',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: demoModified,
                            onReset: () {
                              setState(() => _cleanDemoMode = defDemo);
                              _updateSetting('global', 'sysui_demo_allowed', defDemo ? '1' : '0');
                            },
                            defaultHint: defDemo ? 'On' : 'Off',
                            child: Switch(
                              value: _cleanDemoMode,
                              activeColor: demoModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _cleanDemoMode = val);
                                _updateSetting('global', 'sysui_demo_allowed', val ? '1' : '0');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 📱 Force Split-Screen Apps Card
                          _buildQuickTweakCard(
                            title: '📱 FORCE SPLIT-SCREEN APPS',
                            riskLevel: SettingRiskLevel.warning,
                            isModified: splitModified,
                            onReset: () {
                              setState(() => _forceSplitScreen = defSplit);
                              _updateSetting('global', 'force_resizable_activities', defSplit ? '1' : '0');
                            },
                            defaultHint: defSplit ? 'Forced' : 'Default',
                            child: Switch(
                              value: _forceSplitScreen,
                              activeColor: splitModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _forceSplitScreen = val);
                                _updateSetting('global', 'force_resizable_activities', val ? '1' : '0');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // ☀️ Screen Brightness Card
                          _buildQuickTweakCard(
                            title: '☀️ SCREEN BRIGHTNESS',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: brightnessModified,
                            onReset: () {
                              setState(() => _screenBrightness = defBrightness);
                              _updateSetting('system', 'screen_brightness', defBrightness.round().toString());
                            },
                            defaultHint: "${defBrightness.round()}",
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("${_screenBrightness.round()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 120,
                                  child: Slider(
                                    value: _screenBrightness.clamp(0.0, 255.0),
                                    min: 0.0,
                                    max: 255.0,
                                    activeColor: brightnessModified ? const Color(0xFF10B981) : Colors.white,
                                    onChanged: (val) {
                                      setState(() => _screenBrightness = val);
                                      _updateSetting('system', 'screen_brightness', val.round().toString());
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // ⏱️ Screen Timeout Card
                          _buildQuickTweakCard(
                            title: '⏱️ SCREEN TIMEOUT',
                            riskLevel: SettingRiskLevel.warning,
                            isModified: timeoutModified,
                            onReset: () {
                              setState(() => _screenTimeoutMs = defTimeout);
                              _updateSetting('system', 'screen_off_timeout', defTimeout.toString());
                            },
                            defaultHint: "${defTimeout ~/ 1000}s",
                            child: DropdownButton<int>(
                              value: [15000, 30000, 60000, 300000, 600000, 1800000, 86400000].contains(_screenTimeoutMs) ? _screenTimeoutMs : 60000,
                              dropdownColor: const Color(0xFF121622),
                              underline: const SizedBox(),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              items: const [
                                DropdownMenuItem(value: 15000, child: Text('15 Seconds')),
                                DropdownMenuItem(value: 30000, child: Text('30 Seconds')),
                                DropdownMenuItem(value: 60000, child: Text('1 Minute')),
                                DropdownMenuItem(value: 300000, child: Text('5 Minutes')),
                                DropdownMenuItem(value: 600000, child: Text('10 Minutes')),
                                DropdownMenuItem(value: 1800000, child: Text('30 Minutes')),
                                DropdownMenuItem(value: 86400000, child: Text('Never (24 Hours)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _screenTimeoutMs = val);
                                  _updateSetting('system', 'screen_off_timeout', val.toString());
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // ⚡ Stay Awake Card
                          _buildQuickTweakCard(
                            title: '⚡ STAY AWAKE ON USB',
                            riskLevel: SettingRiskLevel.warning,
                            isModified: stayAwakeModified,
                            onReset: () {
                              setState(() => _stayAwake = defStayAwake);
                              _updateSetting('global', 'stay_on_while_plugged_in', defStayAwake ? '3' : '0');
                            },
                            defaultHint: defStayAwake ? 'On' : 'Off',
                            child: Switch(
                              value: _stayAwake,
                              activeColor: stayAwakeModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _stayAwake = val);
                                _updateSetting('global', 'stay_on_while_plugged_in', val ? '3' : '0');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 🔄 Auto-Rotate Card
                          _buildQuickTweakCard(
                            title: '🔄 AUTO-ROTATE SCREEN',
                            riskLevel: SettingRiskLevel.safe,
                            isModified: autoRotateModified,
                            onReset: () {
                              setState(() => _autoRotate = defAutoRotate);
                              _updateSetting('system', 'accelerometer_rotation', defAutoRotate ? '1' : '0');
                            },
                            defaultHint: defAutoRotate ? 'On' : 'Off',
                            child: Switch(
                              value: _autoRotate,
                              activeColor: autoRotateModified ? const Color(0xFF10B981) : Colors.white,
                              onChanged: (val) {
                                setState(() => _autoRotate = val);
                                _updateSetting('system', 'accelerometer_rotation', val ? '1' : '0');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 🛡️ Private AdBlock DNS Card
                          _buildQuickTweakCard(
                            title: '🛡️ AD-BLOCK PRIVATE DNS',
                            riskLevel: SettingRiskLevel.warning,
                            isModified: privateDnsModified,
                            onReset: () {
                              setState(() => _privateDnsHost = defPrivateDns);
                              if (defPrivateDns.isEmpty) {
                                _updateSetting('global', 'private_dns_mode', 'off');
                                _updateSetting('global', 'private_dns_specifier', '');
                              } else {
                                _updateSetting('global', 'private_dns_mode', 'hostname');
                                _updateSetting('global', 'private_dns_specifier', defPrivateDns);
                              }
                            },
                            defaultHint: defPrivateDns.isEmpty ? 'Off' : defPrivateDns,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 140,
                                  child: Text(
                                    _privateDnsHost.isEmpty ? 'Off' : _privateDnsHost,
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                                  color: const Color(0xFF121622),
                                  onSelected: (val) {
                                    setState(() => _privateDnsHost = val);
                                    if (val.isEmpty) {
                                      _updateSetting('global', 'private_dns_mode', 'off');
                                      _updateSetting('global', 'private_dns_specifier', '');
                                    } else {
                                      _updateSetting('global', 'private_dns_mode', 'hostname');
                                      _updateSetting('global', 'private_dns_specifier', val);
                                    }
                                  },
                                  itemBuilder: (ctx) => const [
                                    PopupMenuItem(value: '', child: Text('Off')),
                                    PopupMenuItem(value: 'dns.adguard.com', child: Text('AdGuard (Block Ads)')),
                                    PopupMenuItem(value: 'family.adguard-dns.com', child: Text('AdGuard Family (Block Adult)')),
                                    PopupMenuItem(value: 'one.one.one.one', child: Text('Cloudflare 1.1.1.1')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                    onPressed: () => _scrollQuickTweaks(350),
                    tooltip: 'Scroll Track Right',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Namespace Selectors & Search Input Bar
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildNamespaceTab('TWEAKS', 'tweaks'),
                              const SizedBox(width: 8),
                              _buildNamespaceTab('GLOBAL', 'global'),
                              const SizedBox(width: 8),
                              _buildNamespaceTab('SECURE', 'secure'),
                              const SizedBox(width: 8),
                              _buildNamespaceTab('SYSTEM', 'system'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          onChanged: (val) => setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText: 'Search raw settings (e.g. anim, wifi, dark, battery)...',
                            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                            prefixIcon: const Icon(Icons.search, color: Colors.white),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.grey),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF121622),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF1F2636))),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      _buildNamespaceTab('TWEAKS', 'tweaks'),
                      const SizedBox(width: 8),
                      _buildNamespaceTab('GLOBAL', 'global'),
                      const SizedBox(width: 8),
                      _buildNamespaceTab('SECURE', 'secure'),
                      const SizedBox(width: 8),
                      _buildNamespaceTab('SYSTEM', 'system'),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          onChanged: (val) => setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText: 'Search raw settings (e.g. anim, wifi, dark, battery)...',
                            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                            prefixIcon: const Icon(Icons.search, color: Colors.white),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.grey),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF121622),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF1F2636))),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // Bottom Section: Interactive Raw Settings Explorer Table
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : filteredEntries.isEmpty
                  ? Center(
                      child: Text(
                        widget.selectedDeviceSerial == null
                            ? 'Please connect an Android device to view hidden settings'
                            : 'No settings keys found matching "$_searchQuery"',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      cacheExtent: 500,
                      padding: const EdgeInsets.all(12),
                      itemCount: filteredEntries.length,
                      separatorBuilder: (ctx, idx) => const SizedBox(height: 6),
                      itemBuilder: (ctx, idx) {
                        final entry = filteredEntries[idx];
                        final targetNs = (_selectedNamespace == 'tweaks')
                            ? (['show_touches', 'pointer_location', 'peak_refresh_rate', 'screen_brightness', 'screen_off_timeout', 'accelerometer_rotation'].contains(entry.key) ? 'system' : 'global')
                            : _selectedNamespace;
                        final defVal = _defaultsCache[targetNs]?[entry.key];

                        return _SettingRowWidget(
                          key: ValueKey("${_selectedNamespace}_${entry.key}"),
                          settingKey: entry.key,
                          settingValue: entry.value,
                          defaultValue: defVal,
                          namespace: targetNs,
                          onUpdate: _updateSetting,
                          onReset: _resetSettingToDefault,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildQuickTweakCard({
    required String title,
    required Widget child,
    required SettingRiskLevel riskLevel,
    bool isModified = false,
    VoidCallback? onReset,
    String? defaultHint,
  }) {
    Color riskColor = const Color(0xFF10B981); // Green (Safe)
    IconData riskIcon = Icons.check_circle_outline;

    if (riskLevel == SettingRiskLevel.critical) {
      riskColor = const Color(0xFFEF4444); // Red (Critical)
      riskIcon = Icons.report_problem;
    } else if (riskLevel == SettingRiskLevel.warning) {
      riskColor = const Color(0xFFF59E0B); // Yellow (Caution)
      riskIcon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121622),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isModified ? const Color(0xFF10B981) : const Color(0xFF1F2636),
          width: isModified ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isModified ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Icon(riskIcon, color: riskColor, size: 11),
              if (isModified && onReset != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onReset,
                  child: Tooltip(
                    message: defaultHint != null ? 'Reset to phone default ($defaultHint)' : 'Reset to phone default',
                    child: const Icon(Icons.restore, color: Color(0xFF10B981), size: 14),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _buildNamespaceTab(String label, String nsKey) {
    final isSelected = _selectedNamespace == nsKey;
    return InkWell(
      onTap: () => setState(() => _selectedNamespace = nsKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF121622),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? Colors.white : const Color(0xFF1F2636)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _SettingRowWidget extends StatefulWidget {
  final String settingKey;
  final String settingValue;
  final String? defaultValue;
  final String namespace;
  final Function(String ns, String key, String value) onUpdate;
  final Function(String ns, String key) onReset;

  const _SettingRowWidget({
    Key? key,
    required this.settingKey,
    required this.settingValue,
    this.defaultValue,
    required this.namespace,
    required this.onUpdate,
    required this.onReset,
  }) : super(key: key);

  @override
  State<_SettingRowWidget> createState() => _SettingRowWidgetState();
}

class _SettingRowWidgetState extends State<_SettingRowWidget> {
  late TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.settingValue);
  }

  @override
  void didUpdateWidget(covariant _SettingRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingValue != widget.settingValue) {
      _textCtrl.text = widget.settingValue;
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBool = widget.settingValue == '0' || widget.settingValue == '1';
    final isBoolActive = widget.settingValue == '1';
    final isModified = widget.defaultValue != null && widget.defaultValue != widget.settingValue;

    final risk = SettingRiskHelper.getRiskLevel(widget.settingKey);
    Color riskColor = const Color(0xFF10B981); // Green (Safe)
    IconData riskIcon = Icons.check_circle_outline;
    String riskLabel = 'SAFE';

    if (risk == SettingRiskLevel.critical) {
      riskColor = const Color(0xFFEF4444); // Red (Critical)
      riskIcon = Icons.report_problem;
      riskLabel = 'HIGH RISK';
    } else if (risk == SettingRiskLevel.warning) {
      riskColor = const Color(0xFFF59E0B); // Yellow (Caution)
      riskIcon = Icons.warning_amber_rounded;
      riskLabel = 'CAUTION';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121622),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isModified ? const Color(0xFF10B981) : const Color(0xFF1F2636),
          width: isModified ? 2 : 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 480;

          final headerInfo = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  SelectableText(
                    widget.settingKey,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: riskColor, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(riskIcon, color: riskColor, size: 10),
                        const SizedBox(width: 3),
                        Text(riskLabel, style: TextStyle(color: riskColor, fontSize: 8, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  if (isModified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF064E3B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF10B981)),
                      ),
                      child: const Text('MODIFIED', style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                isModified ? "${widget.namespace.toUpperCase()} • Default: ${widget.defaultValue}" : widget.namespace.toUpperCase(),
                style: TextStyle(color: isModified ? const Color(0xFF10B981) : const Color(0xFF6B7280), fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          );

          final inputControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isModified)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    icon: const Icon(Icons.restore, color: Color(0xFF10B981), size: 18),
                    tooltip: 'Reset to phone default (${widget.defaultValue})',
                    onPressed: () => widget.onReset(widget.namespace, widget.settingKey),
                  ),
                ),
              if (isBool)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isBoolActive ? '1 (ENABLED)' : '0 (DISABLED)',
                      style: TextStyle(color: isBoolActive ? Colors.greenAccent : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: isBoolActive,
                      activeThumbColor: isModified ? const Color(0xFF10B981) : Colors.white,
                      onChanged: (val) {
                        widget.onUpdate(widget.namespace, widget.settingKey, val ? '1' : '0');
                      },
                    ),
                  ],
                )
              else
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: TextField(
                          controller: _textCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            filled: true,
                            fillColor: const Color(0xFF0B0C10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF1F2636))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2638), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                        onPressed: () {
                          widget.onUpdate(widget.namespace, widget.settingKey, _textCtrl.text.trim());
                        },
                        child: const Text('SAVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerInfo,
                const SizedBox(height: 8),
                inputControls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 4, child: headerInfo),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: inputControls),
            ],
          );
        },
      ),
    );
  }
}
