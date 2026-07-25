import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/smart_tv_device.dart';

class SsdpScanner {
  static const String ssdpMulticastAddress = '239.255.255.250';
  static const int ssdpPort = 1900;

  /// Performs an SSDP M-SEARCH broadcast to discover Smart TVs on the local Wi-Fi subnet.
  Future<List<SmartTvDevice>> scanForDevices({Duration timeout = const Duration(seconds: 4)}) async {
    final List<SmartTvDevice> discovered = [];
    RawDatagramSocket? socket;

    final String searchTargetRoku = 'roku:ecp';
    final String searchTargetDial = 'urn:dial-multiscreen-org:service:dial:1';
    final String searchTargetAll = 'ssdp:all';

    final List<String> searchTargets = [
      searchTargetRoku,
      searchTargetDial,
      searchTargetAll,
    ];

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastHops = 4;

      final Map<String, String> responseLocations = {};

      final subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data);
            final ip = datagram.address.address;
            final location = _extractHeader(response, 'LOCATION');
            final server = _extractHeader(response, 'SERVER') ?? '';
            final st = _extractHeader(response, 'ST') ?? '';

            if (location != null && !responseLocations.containsKey(ip)) {
              responseLocations[ip] = location;

              // Immediate Roku detection from SSDP server/ST header
              if (server.toLowerCase().contains('roku') || st.contains('roku')) {
                discovered.add(SmartTvDevice(
                  id: 'roku_$ip',
                  name: 'Roku Smart TV',
                  brand: TvBrand.roku,
                  ipAddress: ip,
                  port: 8060,
                  manufacturer: 'Roku',
                  discoveryMethod: 'SSDP',
                  lastSeen: DateTime.now(),
                ));
              }
            }
          }
        }
      });

      // Send M-SEARCH for each target
      for (final st in searchTargets) {
        final mSearchPayload =
            'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $ssdpMulticastAddress:$ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 3\r\n'
            'ST: $st\r\n'
            '\r\n';

        final data = utf8.encode(mSearchPayload);
        socket.send(data, InternetAddress(ssdpMulticastAddress), ssdpPort);
      }

      await Future.delayed(timeout);
      await subscription.cancel();
      socket.close();

      // Resolve location XMLs to fetch rich metadata
      for (final entry in responseLocations.entries) {
        final ip = entry.key;
        final locationUrl = entry.value;
        if (!discovered.any((d) => d.ipAddress == ip)) {
          final fetchedDevice = await _fetchDeviceDetailsFromLocation(ip, locationUrl);
          if (fetchedDevice != null) {
            discovered.add(fetchedDevice);
          }
        }
      }
    } catch (_) {
      // Network socket errors handled gracefully
    } finally {
      socket?.close();
    }

    return discovered;
  }

  String? _extractHeader(String rawResponse, String headerName) {
    final lines = rawResponse.split('\r\n');
    for (final line in lines) {
      if (line.toLowerCase().startsWith('${headerName.toLowerCase()}:')) {
        return line.substring(headerName.length + 1).trim();
      }
    }
    return null;
  }

  Future<SmartTvDevice?> _fetchDeviceDetailsFromLocation(String ip, String locationUrl) async {
    try {
      final uri = Uri.parse(locationUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final body = response.body.toLowerCase();
        String name = 'Smart TV ($ip)';
        TvBrand brand = TvBrand.genericDial;

        if (body.contains('roku')) {
          brand = TvBrand.roku;
          name = 'Roku TV';
        } else if (body.contains('samsung')) {
          brand = TvBrand.samsung;
          name = 'Samsung Smart TV';
        } else if (body.contains('lg')) {
          brand = TvBrand.lg;
          name = 'LG webOS TV';
        } else if (body.contains('tcl')) {
          brand = TvBrand.tcl;
          name = 'TCL Google TV';
        } else if (body.contains('android') || body.contains('google')) {
          brand = TvBrand.androidTv;
          name = 'Android TV';
        }

        // Try extracting friendlyName from UPnP XML
        final match = RegExp(r'<friendlyName>(.*?)</friendlyName>', caseSensitive: false).firstMatch(response.body);
        if (match != null && match.group(1) != null) {
          name = match.group(1)!;
        }

        return SmartTvDevice(
          id: '${brand.name}_$ip',
          name: name,
          brand: brand,
          ipAddress: ip,
          port: uri.port > 0 ? uri.port : 8060,
          discoveryMethod: 'SSDP UPnP',
          lastSeen: DateTime.now(),
        );
      }
    } catch (_) {}
    return null;
  }
}
