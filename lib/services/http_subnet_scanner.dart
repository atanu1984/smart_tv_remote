import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/smart_tv_device.dart';

class HttpSubnetScanner {
  /// Fast asynchronous subnet sweep for active TV ports (Roku 8060, Android TV 8008/5555, Samsung 8001, LG 3000)
  Future<List<SmartTvDevice>> sweepSubnet(
    String subnetPrefix, {
    void Function(String message)? onProgress,
  }) async {
    final List<SmartTvDevice> foundDevices = [];
    final List<Future<SmartTvDevice?>> tasks = [];

    onProgress?.call('Scanning local Wi-Fi subnet ($subnetPrefix.1 - $subnetPrefix.254)...');

    // Sweep across 1..254 concurrently
    for (int i = 1; i <= 254; i++) {
      final ip = '$subnetPrefix.$i';
      tasks.add(_probeIp(ip));
    }

    final results = await Future.wait(tasks);
    for (final device in results) {
      if (device != null) {
        foundDevices.add(device);
      }
    }

    return foundDevices;
  }

  Future<SmartTvDevice?> _probeIp(String ip) async {
    // 1. Probe Android TV / Google TV (Port 8008 / 5555)
    final androidDevice = await _probeAndroidTv(ip);
    if (androidDevice != null) return androidDevice;

    // 2. Probe Roku ECP (Port 8060)
    final rokuDevice = await _probeRoku(ip);
    if (rokuDevice != null) return rokuDevice;

    // 3. Probe Samsung Smart TV API (Port 8001)
    final samsungDevice = await _probeSamsung(ip);
    if (samsungDevice != null) return samsungDevice;

    // 4. Probe LG webOS (Port 3000)
    final lgDevice = await _probeLg(ip);
    if (lgDevice != null) return lgDevice;

    return null;
  }

  Future<SmartTvDevice?> _probeAndroidTv(String ip) async {
    // Check port 8008 (Google Cast) — present on Android/Google TV and TCL Google TV
    try {
      final url = Uri.parse('http://$ip:8008/setup/configured_networks');
      final response = await http.get(url).timeout(const Duration(milliseconds: 500));
      if (response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 403) {
        // Detect TCL from response body or headers
        final bodyLower = response.body.toLowerCase();
        final isTcl = bodyLower.contains('tcl') ||
            response.headers.values.any((v) => v.toLowerCase().contains('tcl'));

        return SmartTvDevice(
          id: 'androidtv_$ip',
          name: isTcl ? 'TCL Google TV ($ip)' : 'Android TV ($ip)',
          brand: isTcl ? TvBrand.tcl : TvBrand.androidTv,
          ipAddress: ip,
          port: isTcl ? 6466 : 5555,
          manufacturer: isTcl ? 'TCL Electronics' : 'Google / Android TV',
          discoveryMethod: 'HTTP Port 8008',
          lastSeen: DateTime.now(),
        );
      }
    } catch (_) {}

    // Also check port 6466 (Google TV Remote Service) — TCL Google TVs always have this
    try {
      final socket = await Socket.connect(ip, 6466, timeout: const Duration(milliseconds: 400));
      await socket.close();
      return SmartTvDevice(
        id: 'googletv_$ip',
        name: 'Google TV ($ip)',
        brand: TvBrand.tcl,
        ipAddress: ip,
        port: 6466,
        manufacturer: 'TCL / Google TV',
        discoveryMethod: 'Google TV Remote Port 6466',
        lastSeen: DateTime.now(),
      );
    } catch (_) {}

    return null;
  }

  Future<SmartTvDevice?> _probeRoku(String ip) async {
    try {
      final url = Uri.parse('http://$ip:8060/query/device-info');
      final response = await http.get(url).timeout(const Duration(milliseconds: 600));

      if (response.statusCode == 200 && response.body.contains('<device-info>')) {
        final body = response.body;

        String name = 'Roku TV';
        String? model;
        String? serial;

        final nameMatch = RegExp(r'<friendly-device-name>(.*?)</friendly-device-name>').firstMatch(body);
        final modelMatch = RegExp(r'<model-name>(.*?)</model-name>').firstMatch(body);
        final serialMatch = RegExp(r'<serial-number>(.*?)</serial-number>').firstMatch(body);

        if (nameMatch != null && nameMatch.group(1) != null) {
          name = nameMatch.group(1)!;
        }
        if (modelMatch != null) model = modelMatch.group(1);
        if (serialMatch != null) serial = serialMatch.group(1);

        return SmartTvDevice(
          id: 'roku_$ip',
          name: name,
          brand: TvBrand.roku,
          ipAddress: ip,
          port: 8060,
          modelName: model,
          manufacturer: 'Roku, Inc.',
          serialNumber: serial,
          discoveryMethod: 'HTTP Port 8060',
          lastSeen: DateTime.now(),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<SmartTvDevice?> _probeSamsung(String ip) async {
    try {
      final url = Uri.parse('http://$ip:8001/api/v2/');
      final response = await http.get(url).timeout(const Duration(milliseconds: 500));

      if (response.statusCode == 200 && response.body.toLowerCase().contains('samsung')) {
        return SmartTvDevice(
          id: 'samsung_$ip',
          name: 'Samsung Smart TV',
          brand: TvBrand.samsung,
          ipAddress: ip,
          port: 8001,
          manufacturer: 'Samsung Electronics',
          discoveryMethod: 'HTTP Port 8001',
          lastSeen: DateTime.now(),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<SmartTvDevice?> _probeLg(String ip) async {
    try {
      final url = Uri.parse('http://$ip:3000/');
      final response = await http.get(url).timeout(const Duration(milliseconds: 500));

      if (response.statusCode == 200 || response.statusCode == 404) {
        if (response.body.toLowerCase().contains('webos') || response.headers.values.any((v) => v.toLowerCase().contains('webos'))) {
          return SmartTvDevice(
            id: 'lg_$ip',
            name: 'LG webOS TV',
            brand: TvBrand.lg,
            ipAddress: ip,
            port: 3000,
            manufacturer: 'LG Electronics',
            discoveryMethod: 'HTTP Port 3000',
            lastSeen: DateTime.now(),
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
