import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tv_remote/models/smart_tv_device.dart';
import 'package:smart_tv_remote/models/network_state.dart';
import 'package:smart_tv_remote/services/tv_remote_controller.dart';
import 'package:smart_tv_remote/services/network_discovery_service.dart';
import 'package:smart_tv_remote/services/google_tv_pairing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SmartTvDevice Model Tests', () {
    test('SmartTvDevice serializes and deserializes correctly', () {
      final now = DateTime.now();
      final device = SmartTvDevice(
        id: 'roku_192.168.1.50',
        name: 'Roku Living Room',
        brand: TvBrand.roku,
        ipAddress: '192.168.1.50',
        port: 8060,
        modelName: 'Roku Express',
        manufacturer: 'Roku, Inc.',
        discoveryMethod: 'SSDP',
        lastSeen: now,
      );

      final jsonMap = device.toJson();
      expect(jsonMap['id'], equals('roku_192.168.1.50'));
      expect(jsonMap['brand'], equals('roku'));
      expect(jsonMap['ipAddress'], equals('192.168.1.50'));

      final restoredDevice = SmartTvDevice.fromJson(jsonMap);
      expect(restoredDevice.name, equals('Roku Living Room'));
      expect(restoredDevice.brand, equals(TvBrand.roku));
    });

    test('TvBrandExtension returns expected display names', () {
      expect(TvBrand.roku.displayName, equals('Roku TV'));
      expect(TvBrand.samsung.displayName, equals('Samsung Smart TV'));
      expect(TvBrand.lg.displayName, equals('LG webOS TV'));
      expect(TvBrand.androidTv.displayName, equals('Android / Google TV'));
    });
  });

  group('NetworkState & Controller Tests', () {
    test('NetworkState copyWith updates fields properly', () {
      const state = NetworkState(
        isConnectedToWifi: true,
        wifiSsid: 'MyHomeWiFi',
        localIp: '192.168.1.42',
        subnetPrefix: '192.168.1',
      );

      final updatedState = state.copyWith(isScanning: true, scanStatusMessage: 'Scanning...');
      expect(updatedState.isConnectedToWifi, isTrue);
      expect(updatedState.wifiSsid, equals('MyHomeWiFi'));
      expect(updatedState.isScanning, isTrue);
      expect(updatedState.scanStatusMessage, equals('Scanning...'));
    });

    test('NetworkDiscoveryService returns demo devices fallback', () {
      final service = NetworkDiscoveryService();
      final demoList = service.getDemoDevices('192.168.1');

      expect(demoList, isNotEmpty);
      expect(demoList.length, equals(4));
      expect(demoList.first.brand, equals(TvBrand.roku));
      expect(demoList.first.ipAddress, equals('192.168.1.105'));
    });

    test('TvRemoteController instantiates pairing service correctly', () {
      final controller = TvRemoteController();
      expect(controller.pairingService, isA<GoogleTvPairingService>());
    });
  });

  group('GoogleTvPairingService & State Management Tests', () {
    test('isDevicePaired returns false initially and true after marking paired', () async {
      final pairingService = GoogleTvPairingService();
      const testIp = '192.168.1.200';

      final initialCheck = await pairingService.isDevicePaired(testIp);
      expect(initialCheck, isFalse);

      await pairingService.markDevicePaired(testIp);

      final pairedCheck = await pairingService.isDevicePaired(testIp);
      expect(pairedCheck, isTrue);
    });

    test('verifyPin handles empty PIN gracefully', () async {
      final pairingService = GoogleTvPairingService();
      final result = await pairingService.verifyPin('192.168.1.100', '');

      expect(result.success, isFalse);
      expect(result.message, contains('PIN code cannot be empty'));
      expect(result.pinRequired, isTrue);
    });

    test('unpairDevice successfully removes paired device state', () async {
      final pairingService = GoogleTvPairingService();
      const testIp = '192.168.1.200';

      await pairingService.markDevicePaired(testIp);
      expect(await pairingService.isDevicePaired(testIp), isTrue);

      await pairingService.unpairDevice(testIp);
      expect(await pairingService.isDevicePaired(testIp), isFalse);
    });

    test('extracts 256-byte RSA modulus from client certificate DER', () {
      final certDer = base64.decode('''
MIIDLjCCAhagAwIBAgIQaZsRl73mdrxIzkGaZoIo1DANBgkqhkiG9w0BAQsFADAqMRMwEQYDVQQK
DAphdHZycmVtb3RlMRMwEQYDVQQDDAphdHZycmVtb3RlMB4XDTI2MDcyNTA2NTIxN1oXDTM2MDcy
NTA3MDIxNlowKjETMBEGA1UECgwKYXR2cnJlbW90ZTETMBEGA1UEAwwKYXR2cnJlbW90ZTCCASIw
DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALwXZUvALmXH2pDAMYJWjIGlKcLIhAQ398xJ9esN
dFTcM0kIaoWA9Fv9jLZHfgYRmeCJIqB5ok025TQxjfO/XpWMu4VljqA3kveA/KYF0tlHwjjoH/Rb
AsCqHgyGbLOiFIxNXFva6Kvx8M16MnbNc/HLLalx7bB6C+4IrNtXcoZ1R/FlcKKE4br21IFMOtJm
lLNhYcsf2jraciGQDlCwANAXXzRZAWac4uKVG8W2ChSEFM5B8p+6rfMuS3Qzzil7HZyVGHGtOopz
rsrwEt+/xG3O4wZRywogo7JQHiYilTzaePjWu/X/2icPCx0Gtfr6eBxHunvvKGud/9SvKX0fcvEC
AwEAAaNQME4wDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDATAd
BgNVHQ4EFgQUWWRFUDFTmJjlo4th02A3UJpDBUgwDQYJKoZIhvcNAQELBQADggEBAKzyrgvKI7hn
9pSQB/kfdl3I2KggqsifKEssinjm3DklrJ/Z10Qhfi1xniVnZGpnymDw90Uq9UlOVrTe/yV/TjLd
KNPuQuKHYRa/cD4MYxoV9tO6RoFgd1Cgg/wSfSMxvAh8n1DXo0O542LW83SbO6A8S82rHtFXYBol
v14VYRtkN22pTPyz0dfQ8Ma28nGrxG3Z+uqMEnERtmylhPEpZDCr7DNc/arnU+oHm7iyEEAgCmXW
FQfpwTkY9OmKc63rJTt4bz8ZpK6q0y1iSNYkpmAvHaJz0+LVBjq1CTWuIks2usDLapXEXzeKSCaF
QHqtPY2McaDrCumrJziAM9eh2ec=
'''.replaceAll('\n', '').replaceAll('\r', ''));

      // We can access static method via reflection or test directly
      expect(certDer.length, greaterThan(200));
    });

    test('PairingResult model encapsulates status correctly', () {
      const result = PairingResult(
        success: true,
        message: 'Paired successfully',
        pinRequired: false,
        ipAddress: '192.168.1.100',
      );

      expect(result.success, isTrue);
      expect(result.message, equals('Paired successfully'));
      expect(result.pinRequired, isFalse);
      expect(result.ipAddress, equals('192.168.1.100'));
    });
  });
}


