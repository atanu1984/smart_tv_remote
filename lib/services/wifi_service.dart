import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/network_state.dart';

class WifiService {
  final Connectivity _connectivity = Connectivity();
  final NetworkInfo _networkInfo = NetworkInfo();

  /// Checks whether the device is connected to Wi-Fi and calculates local IP & subnet prefix.
  Future<NetworkState> checkWifiStatus() async {
    try {
      final List<ConnectivityResult> results = await _connectivity.checkConnectivity();
      final bool isWifi = results.contains(ConnectivityResult.wifi);

      String? wifiSsid;
      String? localIp;
      String? subnetPrefix;

      if (isWifi) {
        try {
          wifiSsid = await _networkInfo.getWifiName();
          // Clean quotes if returned like '"Home-WiFi"'
          if (wifiSsid != null && wifiSsid.startsWith('"') && wifiSsid.endsWith('"')) {
            wifiSsid = wifiSsid.substring(1, wifiSsid.length - 1);
          }
        } catch (_) {}

        try {
          localIp = await _networkInfo.getWifiIP();
        } catch (_) {}

        // Fallback: search system network interfaces if NetworkInfo fails
        localIp ??= await _getLocalIpFromInterfaces();
      } else {
        // Fallback check: check network interfaces directly (e.g. on desktop/emulators)
        localIp = await _getLocalIpFromInterfaces();
      }

      // Format clean SSID or fallback name
      if (wifiSsid == null || wifiSsid.isEmpty || wifiSsid == '<unknown ssid>') {
        wifiSsid = isWifi ? 'Home Wi-Fi Network' : 'Local Network';
      }

      if (localIp != null && localIp.isNotEmpty) {
        final parts = localIp.split('.');
        if (parts.length == 4) {
          subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        }
      }

      return NetworkState(
        isConnectedToWifi: isWifi || (localIp != null && !localIp.startsWith('127.')),
        wifiSsid: wifiSsid,
        localIp: localIp,
        subnetPrefix: subnetPrefix,
      );
    } catch (e) {
      // Direct local IP lookup fallback
      final fallbackIp = await _getLocalIpFromInterfaces();
      String? subnet;
      if (fallbackIp != null) {
        final parts = fallbackIp.split('.');
        if (parts.length == 4) {
          subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
        }
      }

      return NetworkState(
        isConnectedToWifi: fallbackIp != null && !fallbackIp.startsWith('127.'),
        wifiSsid: 'Home Wi-Fi',
        localIp: fallbackIp ?? '192.168.1.100',
        subnetPrefix: subnet ?? '192.168.1',
      );
    }
  }

  /// Helper to find non-loopback IPv4 address from active network interfaces
  Future<String?> _getLocalIpFromInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
              return ip;
            }
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return null;
  }
}
