import 'package:flutter/material.dart';
import 'adb_manager.dart';

class WifiAdbScreen extends StatefulWidget {
  final List<DeviceInfo> connectedDevices;
  final VoidCallback onDevicesUpdated;

  const WifiAdbScreen({
    Key? key,
    required this.connectedDevices,
    required this.onDevicesUpdated,
  }) : super(key: key);

  @override
  State<WifiAdbScreen> createState() => _WifiAdbScreenState();
}

class _WifiAdbScreenState extends State<WifiAdbScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _pairIpPortController = TextEditingController();
  final TextEditingController _pairCodeController = TextEditingController();

  final TextEditingController _connectIpPortController = TextEditingController();

  String? _selectedUsbSerial;
  bool _isPairing = false;
  bool _isConnecting = false;
  bool _isEnablingTcpip = false;

  List<String> _mdnsServices = [];
  bool _isScanningMdns = false;

  @override
  void initState() {
    super.initState();
    _scanMdns();
  }

  Future<void> _scanMdns() async {
    setState(() => _isScanningMdns = true);
    final list = await AdbManager.scanWifiMdns();
    if (mounted) {
      setState(() {
        _mdnsServices = list;
        _isScanningMdns = false;
      });
    }
  }

  Future<void> _handlePair() async {
    final ipPort = _pairIpPortController.text.trim();
    final code = _pairCodeController.text.trim();

    if (ipPort.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter IP:Port and Pairing Code!')),
      );
      return;
    }

    setState(() => _isPairing = true);
    final success = await AdbManager.pairWifi(ipPort, code);
    setState(() => _isPairing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? "🟢 Paired successfully with $ipPort!" : "🔴 Pairing failed for $ipPort")),
      );
      if (success) {
        widget.onDevicesUpdated();
      }
    }
  }

  Future<void> _handleConnect([String? customIpPort]) async {
    final ipPort = customIpPort ?? _connectIpPortController.text.trim();
    if (ipPort.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter target IP:Port!')),
      );
      return;
    }

    setState(() => _isConnecting = true);
    final success = await AdbManager.connectWifi(ipPort);
    setState(() => _isConnecting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? "🟢 Connected to $ipPort!" : "🔴 Connection failed for $ipPort")),
      );
      if (success) {
        widget.onDevicesUpdated();
      }
    }
  }

  Future<void> _handleEnableTcpip() async {
    final usbDevices = widget.connectedDevices.where((d) => !d.isWifi).toList();
    final serial = _selectedUsbSerial ?? (usbDevices.isNotEmpty ? usbDevices.first.serial : null);

    if (serial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please plug in a USB Android device first!')),
      );
      return;
    }

    setState(() => _isEnablingTcpip = true);
    final success = await AdbManager.enableUsbTcpip(serial, 5555);
    setState(() => _isEnablingTcpip = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? "🟢 Port 5555 enabled on $serial! You can now unplug USB and connect via Wi-Fi." : "🔴 Failed to enable TCP mode.")),
      );
      if (success) {
        widget.onDevicesUpdated();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final usbDevices = widget.connectedDevices.where((d) => !d.isWifi).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. One-Click USB-to-Wireless Converter Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.usb, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'ONE-CLICK USB-TO-WIRELESS SWITCH (PORT 5555)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF242424),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () {
                        widget.onDevicesUpdated();
                        _scanMdns();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🔄 Refreshing connected ADB & Wi-Fi devices...'), duration: Duration(seconds: 2)),
                        );
                      },
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('REFRESH DEVICES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Plug in USB cable once, click button to enable wireless port 5555, then unplug USB!',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                ),
                const SizedBox(height: 12),
                if (usbDevices.isEmpty)
                  const Text('No USB devices connected. Plug in a USB cable to enable wireless mode.', style: TextStyle(color: Colors.grey, fontSize: 12))
                else
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedUsbSerial ?? usbDevices.first.serial,
                          dropdownColor: const Color(0xFF121622),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF0B0C10),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1F2636))),
                          ),
                          items: usbDevices.map((d) => DropdownMenuItem(value: d.serial, child: Text(d.displayName))).toList(),
                          onChanged: (val) => setState(() => _selectedUsbSerial = val),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onPressed: _isEnablingTcpip ? null : _handleEnableTcpip,
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('Enable Wireless Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Android 11+ Wireless Debugging Pairing Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.phonelink_setup, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'ANDROID 11+ WIRELESS PAIRING (NO CABLE NEEDED)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'On Phone: Settings -> Developer Options -> Wireless Debugging -> Pair with pairing code',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _pairIpPortController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'IP:Port (e.g. 192.168.1.50:38291)',
                          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                          filled: true,
                          fillColor: const Color(0xFF0D0D0D),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D2D2D))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _pairCodeController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '6-Digit Code (e.g. 849201)',
                          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                          filled: true,
                          fillColor: const Color(0xFF0B0C10),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1F2636))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onPressed: _isPairing ? null : _handlePair,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Pair Device', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Connect Wireless Device Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wifi, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'CONNECT WIRELESS DEVICE (DIRECT IP)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _connectIpPortController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'IP:Port (e.g. 192.168.1.50:5555 or 192.168.1.50:41203)',
                          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                          filled: true,
                          fillColor: const Color(0xFF0D0D0D),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D2D2D))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onPressed: _isConnecting ? null : () => _handleConnect(),
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. mDNS Auto-Discovered Wi-Fi Devices Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.radar, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'mDNS LOCAL WI-FI BROADCAST SCANNER',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _scanMdns,
                      tooltip: 'Re-scan local Wi-Fi mDNS broadcasts',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Auto-detects phones broadcasting Wireless Debugging signals on your local Wi-Fi network',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                ),
                const SizedBox(height: 10),
                if (_isScanningMdns)
                  const Center(child: CircularProgressIndicator(color: Colors.white))
                else if (_mdnsServices.isEmpty)
                  const Text('No mDNS broadcasting devices found on local Wi-Fi.', style: TextStyle(color: Colors.grey, fontSize: 12))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _mdnsServices.length,
                    itemBuilder: (ctx, idx) {
                      final service = _mdnsServices[idx];
                      return Card(
                        color: const Color(0xFF202020),
                        margin: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            leading: const Icon(Icons.cell_wifi, color: Color(0xFF9C27B0)),
                            title: Text(service, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF9C27B0),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              onPressed: () {
                                final parts = service.split(RegExp(r'\s+'));
                                if (parts.length >= 2) {
                                  _connectIpPortController.text = parts.last;
                                  _handleConnect(parts.last);
                                }
                              },
                              child: const Text('Connect', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
