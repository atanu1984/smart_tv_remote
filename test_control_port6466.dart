import 'dart:convert';
import 'dart:io';

void main() async {
  const ip = '192.168.0.213';
  print('=== TESTING DIRECT CONTROL SESSION ON PORT 6466 ($ip:6466) ===');

  final pfxBytes = File('C:/Code/smart_tv_remote/app_client_cert.pfx').readAsBytesSync();
  final secContext = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(pfxBytes, password: 'temp1234')
    ..usePrivateKeyBytes(pfxBytes, password: 'temp1234');

  try {
    final socket = await SecureSocket.connect(
      ip,
      6466,
      context: secContext,
      onBadCertificate: (cert) => true,
      timeout: const Duration(seconds: 5),
    );

    print('1. Connected mTLS socket to $ip:6466!');

    final List<int> buffer = [];
    socket.listen((data) {
      buffer.addAll(data);
      final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      print('  TV Port 6466 Received (${data.length}B): $hex');
    });

    List<int> encodeVarint(int value) {
      final List<int> res = [];
      while (value >= 0x80) {
        res.add((value & 0x7F) | 0x80);
        value >>= 7;
      }
      res.add(value & 0x7F);
      return res;
    }

    List<int> encodeTag(int fieldNumber, int wireType) {
      return encodeVarint((fieldNumber << 3) | wireType);
    }

    List<int> wrapWithVarintLength(List<int> payload) {
      return [...encodeVarint(payload.length), ...payload];
    }

    // Step 1: Send RemoteConfigure
    print('2. Sending RemoteConfigure...');
    final info = [...encodeTag(1, 2), ...encodeVarint(utf8.encode('Smart TV Remote').length), ...utf8.encode('Smart TV Remote')];
    final cfgInner = [...encodeTag(1, 2), ...encodeVarint(info.length), ...info];
    final cfgOuter = [...encodeTag(1, 2), ...encodeVarint(cfgInner.length), ...cfgInner];
    socket.add(wrapWithVarintLength(cfgOuter));
    await socket.flush();
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: Send RemoteSetActive
    print('3. Sending RemoteSetActive (active = 1)...');
    final activeInner = [...encodeTag(1, 0), ...encodeVarint(1)];
    final activeOuter = [...encodeTag(2, 2), ...encodeVarint(activeInner.length), ...activeInner];
    socket.add(wrapWithVarintLength(activeOuter));
    await socket.flush();
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: Send Keycode 24 (VOLUME_UP)
    print('4. Sending Keycode 24 (VOLUME_UP)... Look at your TV!');
    final keyInner = [
      ...encodeTag(1, 0), ...encodeVarint(24), // VOLUME_UP
      ...encodeTag(2, 0), ...encodeVarint(1),  // direction SHORT (click)
    ];
    final keyOuter = [...encodeTag(3, 2), ...encodeVarint(keyInner.length), ...keyInner];
    socket.add(wrapWithVarintLength(keyOuter));
    await socket.flush();

    await Future.delayed(const Duration(milliseconds: 1500));
    socket.destroy();
    print('\nDone testing Port 6466.');
  } catch (e) {
    print('❌ Port 6466 Error: $e');
  }
}
