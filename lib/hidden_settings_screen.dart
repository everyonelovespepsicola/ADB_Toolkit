import 'package:flutter/material.dart';
import 'adb_manager.dart';
import 'main.dart';

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

class _HiddenSettingsScreenState extends State<HiddenSettingsScreen> {
  String _selectedNamespace = 'global'; // 'global', 'secure', 'system'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Map<String, String>> _settingsCache = {
    'global': {},
    'secure': {},
    'system': {},
  };
  bool _isLoading = false;

  // Quick Tweaks State
  double _animScale = 1.0;
  double _screenBrightness = 128.0;
  int _screenTimeoutMs = 60000;
  bool _stayAwake = false;
  bool _autoRotate = true;
  String _privateDnsHost = '';

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
    if (serial == null) return;

    setState(() => _isLoading = true);

    final globalSettings = await AdbManager.getSettingsList(serial, 'global');
    final secureSettings = await AdbManager.getSettingsList(serial, 'secure');
    final systemSettings = await AdbManager.getSettingsList(serial, 'system');

    if (mounted) {
      setState(() {
        _settingsCache['global'] = globalSettings;
        _settingsCache['secure'] = secureSettings;
        _settingsCache['system'] = systemSettings;

        // Parse Quick Tweaks
        _animScale = double.tryParse(globalSettings['window_animation_scale'] ?? '1.0') ?? 1.0;
        _screenBrightness = double.tryParse(systemSettings['screen_brightness'] ?? '128') ?? 128.0;
        _screenTimeoutMs = int.tryParse(systemSettings['screen_off_timeout'] ?? '60000') ?? 60000;
        _stayAwake = (globalSettings['stay_on_while_plugged_in'] ?? '0') != '0';
        _autoRotate = (systemSettings['accelerometer_rotation'] ?? '1') == '1';
        _privateDnsHost = globalSettings['private_dns_specifier'] ?? '';

        _isLoading = false;
      });
    }
  }

  Future<void> _updateSetting(String namespace, String key, String value) async {
    final serial = widget.selectedDeviceSerial;
    if (serial == null) return;

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
    final currentMap = _settingsCache[_selectedNamespace] ?? {};
    final filteredEntries = currentMap.entries.where((e) {
      final q = _searchQuery.toLowerCase();
      return q.isEmpty || e.key.toLowerCase().contains(q) || e.value.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Top Section: Header & Featured System Quick Tweaks
        Container(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF10131B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'HIDDEN SETTINGS & SYSTEM TWEAKS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: _loadSettings,
                    tooltip: 'Re-fetch Settings from Phone',
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                    onPressed: _showAddSettingModal,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('ADD CUSTOM KEY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Featured Quick Tweaks Row
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  // 🚀 Animation Scale Card
                  _buildQuickTweakCard(
                    title: '🚀 UI ANIMATION SCALE',
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
                            activeColor: Colors.white,
                            onChanged: (val) => _setAnimScale(val),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ☀️ Screen Brightness Card
                  _buildQuickTweakCard(
                    title: '☀️ SCREEN BRIGHTNESS',
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
                            activeColor: Colors.white,
                            onChanged: (val) {
                              setState(() => _screenBrightness = val);
                              _updateSetting('system', 'screen_brightness', val.round().toString());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ⏱️ Screen Timeout Card
                  _buildQuickTweakCard(
                    title: '⏱️ SCREEN TIMEOUT',
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

                  // ⚡ Stay Awake Card
                  _buildQuickTweakCard(
                    title: '⚡ STAY AWAKE ON USB',
                    child: Switch(
                      value: _stayAwake,
                      activeColor: Colors.white,
                      onChanged: (val) {
                        setState(() => _stayAwake = val);
                        _updateSetting('global', 'stay_on_while_plugged_in', val ? '3' : '0');
                      },
                    ),
                  ),

                  // 🔄 Auto-Rotate Card
                  _buildQuickTweakCard(
                    title: '🔄 AUTO-ROTATE SCREEN',
                    child: Switch(
                      value: _autoRotate,
                      activeColor: Colors.white,
                      onChanged: (val) {
                        setState(() => _autoRotate = val);
                        _updateSetting('system', 'accelerometer_rotation', val ? '1' : '0');
                      },
                    ),
                  ),

                  // 🛡️ Private AdBlock DNS Card
                  _buildQuickTweakCard(
                    title: '🛡️ AD-BLOCK PRIVATE DNS',
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
              const SizedBox(height: 12),

              // Namespace Selectors & Search Input Bar
              Row(
                children: [
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
                      padding: const EdgeInsets.all(12),
                      itemCount: filteredEntries.length,
                      separatorBuilder: (ctx, idx) => const SizedBox(height: 6),
                      itemBuilder: (ctx, idx) {
                        final entry = filteredEntries[idx];
                        return _buildSettingRow(entry.key, entry.value);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildQuickTweakCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121622),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F2636)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.bold)),
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

  Widget _buildSettingRow(String key, String value) {
    final isBool = value == '0' || value == '1';
    final isBoolActive = value == '1';
    final textCtrl = TextEditingController(text: value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121622),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1F2636)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                Text(_selectedNamespace.toUpperCase(), style: const TextStyle(color: Color(0xFF6B7280), fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isBool)
            Row(
              children: [
                Text(isBoolActive ? '1 (ENABLED)' : '0 (DISABLED)', style: TextStyle(color: isBoolActive ? Colors.greenAccent : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Switch(
                  value: isBoolActive,
                  activeColor: Colors.white,
                  onChanged: (val) {
                    _updateSetting(_selectedNamespace, key, val ? '1' : '0');
                  },
                ),
              ],
            )
          else
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textCtrl,
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
                      _updateSetting(_selectedNamespace, key, textCtrl.text.trim());
                    },
                    child: const Text('SAVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
