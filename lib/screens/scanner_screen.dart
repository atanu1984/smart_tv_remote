import 'package:flutter/material.dart';
import '../models/smart_tv_device.dart';
import '../models/network_state.dart';
import '../services/google_tv_pairing_service.dart';
import '../services/network_discovery_service.dart';
import '../services/tv_remote_controller.dart';
import '../theme/app_theme.dart';

class ScannerScreen extends StatefulWidget {
  final NetworkState networkState;
  final SmartTvDevice? currentDevice;
  final Function(SmartTvDevice device) onSelectDevice;

  const ScannerScreen({
    Key? key,
    required this.networkState,
    required this.currentDevice,
    required this.onSelectDevice,
  }) : super(key: key);

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final NetworkDiscoveryService _discoveryService = NetworkDiscoveryService();
  final TvRemoteController _remoteController = TvRemoteController();
  final TextEditingController _manualIpController = TextEditingController();
  late AnimationController _radarController;

  bool _isScanning = false;
  bool _isProbingPorts = false;
  String _statusMessage = 'Initializing network scanner...';
  List<SmartTvDevice> _discoveredDevices = [];
  Map<int, bool>? _probedPortResults;
  Set<String> _pairedIps = {}; // tracks which IPs have an active pairing

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _startNetworkScan();
  }

  @override
  void dispose() {
    _radarController.dispose();
    _manualIpController.dispose();
    super.dispose();
  }

  Future<void> _startNetworkScan() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Sweeping local Wi-Fi subnet for TCL, Android TV, Roku, Samsung, LG...';
    });

    final prefix = widget.networkState.subnetPrefix ?? '192.168.1';

    final devices = await _discoveryService.discoverAllDevices(
      subnetPrefix: prefix,
      onStatusUpdate: (msg) {
        if (mounted) {
          setState(() {
            _statusMessage = msg;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _discoveredDevices = devices;
        _isScanning = false;
      });
      // Load paired status for all discovered devices
      _loadPairedStatus(devices);
    }
  }

  Future<void> _loadPairedStatus(List<SmartTvDevice> devices) async {
    final service = _remoteController.pairingService;
    final pairedIps = <String>{};
    for (final d in devices) {
      if (await service.isDevicePaired(d.ipAddress)) {
        pairedIps.add(d.ipAddress);
      }
    }
    if (mounted) setState(() => _pairedIps = pairedIps);
  }

  Future<void> _unpairDevice(SmartTvDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2235),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.link_off_rounded, color: Color(0xFFFF5C5C), size: 22),
            SizedBox(width: 10),
            Text('Remove Pairing', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Remove the pairing for ${device.name}?\n\nYou will need to enter a new PIN on your TV screen to reconnect.',
          style: const TextStyle(color: Color(0xFFB0B8D1), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7594))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Remove'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C5C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _remoteController.pairingService.unpairDevice(device.ipAddress);
      setState(() => _pairedIps.remove(device.ipAddress));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.link_off_rounded, color: Color(0xFFFF5C5C), size: 18),
                const SizedBox(width: 8),
                Text('Pairing removed for ${device.name}. Tap Connect to re-pair.'),
              ],
            ),
            backgroundColor: const Color(0xFF2C1C24),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _runPortDiagnostics() async {
    final targetIp = _manualIpController.text.trim().isNotEmpty
        ? _manualIpController.text.trim()
        : (widget.currentDevice?.ipAddress ?? '192.168.1.100');

    setState(() {
      _isProbingPorts = true;
      _statusMessage = 'Testing active ports on $targetIp...';
    });

    final results = await _remoteController.probeTvPorts(targetIp);

    if (mounted) {
      setState(() {
        _probedPortResults = results;
        _isProbingPorts = false;
        _statusMessage = 'Port diagnostic complete for $targetIp';
      });
    }
  }

  void _connectManualIp() {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;

    final manualDevice = SmartTvDevice(
      id: 'manual_$ip',
      name: 'TCL / Smart TV ($ip)',
      brand: TvBrand.tcl,
      ipAddress: ip,
      port: 8008,
      discoveryMethod: 'Direct IP Entry',
      lastSeen: DateTime.now(),
    );

    widget.onSelectDevice(manualDevice);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Discover & Test Smart TVs', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: _isScanning ? AppTheme.textMuted : AppTheme.primaryCyan,
            ),
            onPressed: _isScanning ? null : _startNetworkScan,
            tooltip: 'Rescan Network',
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),

          // Radar Scan Animation Section
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isScanning)
                  AnimatedBuilder(
                    animation: _radarController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _radarController.value * 2 * 3.14159,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppTheme.primaryCyan.withOpacity(0.4),
                                Colors.transparent,
                              ],
                              stops: const [0.2, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfaceDark,
                    border: Border.all(color: AppTheme.primaryCyan.withOpacity(0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryCyan.withOpacity(0.3),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.tv_rounded, size: 40, color: AppTheme.primaryCyan),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          // Status Message Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isScanning || _isProbingPorts)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                    ),
                  ),
                if (_isScanning || _isProbingPorts) const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Manual Direct IP & Port Diagnostic Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: AppTheme.glassBoxDecoration(borderRadius: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualIpController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Enter TV IP (e.g. 192.168.1.150)',
                            prefixIcon: Icon(Icons.lan_rounded, color: AppTheme.primaryCyan, size: 18),
                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _connectManualIp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryCyan,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'TCL / Android Port Diagnostic:',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: _isProbingPorts ? null : _runPortDiagnostics,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.5)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.network_check_rounded, color: AppTheme.primaryCyan, size: 12),
                              SizedBox(width: 4),
                              Text('Probe TV Ports', style: TextStyle(color: AppTheme.primaryCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_probedPortResults != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _probedPortResults!.entries.map((e) {
                        final isOpen = e.value;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isOpen ? AppTheme.accentGreen.withOpacity(0.2) : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isOpen ? AppTheme.accentGreen : Colors.white24,
                            ),
                          ),
                          child: Text(
                            'Port ${e.key}: ${isOpen ? "OPEN ✅" : "CLOSED"}',
                            style: TextStyle(
                              color: isOpen ? AppTheme.accentGreen : AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: isOpen ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'DISCOVERED SMART TVs',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 6),

                Expanded(
                    child: _discoveredDevices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: AppTheme.textMuted),
                                const SizedBox(height: 12),
                                const Text('No TVs found on local Wi-Fi yet.', style: TextStyle(color: AppTheme.textMuted)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _startNetworkScan,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Scan Again'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryBlue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _discoveredDevices.length,
                            itemBuilder: (context, index) {
                              final device = _discoveredDevices[index];
                              final isSelected = widget.currentDevice?.id == device.id;
                              final isPaired = _pairedIps.contains(device.ipAddress);
                              final isGoogleTv = device.brand == TvBrand.tcl ||
                                  device.brand == TvBrand.androidTv ||
                                  device.brand == TvBrand.genericDial;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0x3300F2FE) : AppTheme.glassSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected ? AppTheme.primaryCyan : AppTheme.cardBorder,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF222638),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            _getIconForBrand(device.brand),
                                            color: isSelected ? AppTheme.primaryCyan : Colors.white70,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      device.name,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                  if (isPaired && isGoogleTv)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.accentGreen.withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: AppTheme.accentGreen.withOpacity(0.5)),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.verified_rounded, color: AppTheme.accentGreen, size: 11),
                                                          SizedBox(width: 3),
                                                          Text('Paired', style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${device.brand.displayName} • ${device.ipAddress}',
                                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                              ),
                                              Text(
                                                'Source: ${device.discoveryMethod}',
                                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () {
                                            widget.onSelectDevice(device);
                                            Navigator.pop(context);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isSelected ? AppTheme.primaryCyan : const Color(0xFF2E344B),
                                            foregroundColor: isSelected ? Colors.black : Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          ),
                                          child: Text(
                                            isSelected ? 'Active' : 'Connect',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Unpair row — only shown for Google/Android TVs that are paired
                                    if (isPaired && isGoogleTv) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Icon(Icons.info_outline_rounded, size: 12, color: AppTheme.textMuted),
                                          const SizedBox(width: 5),
                                          const Expanded(
                                            child: Text(
                                              'Paired — remove to reconnect with new PIN key',
                                              style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _unpairDevice(device),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: const Color(0x22FF5C5C),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0x66FF5C5C)),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.link_off_rounded, size: 12, color: Color(0xFFFF5C5C)),
                                                  SizedBox(width: 4),
                                                  Text('Remove Pairing', style: TextStyle(color: Color(0xFFFF5C5C), fontSize: 11, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
        ],
      ),
    );
  }

  IconData _getIconForBrand(TvBrand brand) {
    switch (brand) {
      case TvBrand.roku:
        return Icons.tv_rounded;
      case TvBrand.samsung:
        return Icons.live_tv_rounded;
      case TvBrand.lg:
        return Icons.connected_tv_rounded;
      case TvBrand.androidTv:
        return Icons.android_rounded;
      case TvBrand.tcl:
        return Icons.cast_rounded;
      case TvBrand.genericDial:
        return Icons.cast_connected_rounded;
    }
  }
}
