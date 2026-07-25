import 'dart:async';
import '../models/smart_tv_device.dart';
import 'ssdp_scanner.dart';
import 'http_subnet_scanner.dart';
import 'wifi_service.dart';

class NetworkDiscoveryService {
  final SsdpScanner _ssdpScanner = SsdpScanner();
  final HttpSubnetScanner _httpScanner = HttpSubnetScanner();
  final WifiService _wifiService = WifiService();

  /// Executes full combined network discovery scan (SSDP + HTTP Subnet sweep + Demo fallback devices)
  Future<List<SmartTvDevice>> discoverAllDevices({
    required String subnetPrefix,
    void Function(String status)? onStatusUpdate,
  }) async {
    final Map<String, SmartTvDevice> deviceMap = {};

    // 1. Run SSDP multicast scan
    onStatusUpdate?.call('Broadcasting SSDP multicast search...');
    try {
      final ssdpDevices = await _ssdpScanner.scanForDevices(timeout: const Duration(seconds: 2));
      for (final dev in ssdpDevices) {
        deviceMap[dev.ipAddress] = dev;
      }
    } catch (_) {}

    // 2. Run HTTP Subnet sweep
    onStatusUpdate?.call('Performing HTTP port sweep on $subnetPrefix.1 - 254...');
    try {
      final httpDevices = await _httpScanner.sweepSubnet(subnetPrefix, onProgress: onStatusUpdate);
      for (final dev in httpDevices) {
        // Prefer rich SSDP metadata if existing, else add sweep result
        if (!deviceMap.containsKey(dev.ipAddress)) {
          deviceMap[dev.ipAddress] = dev;
        }
      }
    } catch (_) {}

    // 3. Fallback Demo Smart TVs (Ensures interactive UI testing capability anytime)
    if (deviceMap.isEmpty) {
      onStatusUpdate?.call('Scan complete. Added simulated demo TVs for testing.');
      final demoDevices = getDemoDevices(subnetPrefix);
      for (final dev in demoDevices) {
        deviceMap[dev.ipAddress] = dev;
      }
    } else {
      onStatusUpdate?.call('Scan complete. Found ${deviceMap.length} device(s).');
    }

    return deviceMap.values.toList();
  }

  /// Provides realistic demo devices for testing UI and commands when no TV is actively listening on local Wi-Fi
  List<SmartTvDevice> getDemoDevices(String subnetPrefix) {
    final now = DateTime.now();
    return [
      SmartTvDevice(
        id: 'demo_roku',
        name: 'Living Room Roku Ultra',
        brand: TvBrand.roku,
        ipAddress: '$subnetPrefix.105',
        port: 8060,
        modelName: 'Roku Ultra (4800X)',
        manufacturer: 'Roku, Inc.',
        serialNumber: 'K089C1234567',
        discoveryMethod: 'SSDP / ECP',
        lastSeen: now,
      ),
      SmartTvDevice(
        id: 'demo_samsung',
        name: 'Master Bedroom QLED 65"',
        brand: TvBrand.samsung,
        ipAddress: '$subnetPrefix.112',
        port: 8001,
        modelName: 'Samsung Q80B 4K',
        manufacturer: 'Samsung Electronics',
        discoveryMethod: 'Smart API HTTP',
        lastSeen: now,
      ),
      SmartTvDevice(
        id: 'demo_lg',
        name: 'Home Theater LG OLED C2',
        brand: TvBrand.lg,
        ipAddress: '$subnetPrefix.120',
        port: 3000,
        modelName: 'LG OLED65C2PUA',
        manufacturer: 'LG Electronics',
        discoveryMethod: 'webOS SSDP',
        lastSeen: now,
      ),
      SmartTvDevice(
        id: 'demo_tcl',
        name: 'TCL Google TV 55"',
        brand: TvBrand.tcl,
        ipAddress: '$subnetPrefix.130',
        port: 6466,
        modelName: 'TCL 55C745',
        manufacturer: 'TCL Electronics',
        discoveryMethod: 'Google TV Remote (Port 6466)',
        lastSeen: now,
      ),
    ];
  }
}
