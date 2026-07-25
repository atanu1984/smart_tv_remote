import 'dart:convert';
import 'dart:io';

void main() async {
  const ip = '192.168.0.213';
  print('=== TESTING FORCED HOME LAUNCHER KEY PRESSES ($ip:6466) ===');

  final pfxBytes = File('C:/Code/smart_tv_remote/app_client_cert.pfx').readAsBytesSync();
  final secContext = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(pfxBytes, password: 'temp1234')
    ..usePrivateKeyBytes(pfxBytes, password: 'temp1234');

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

  try {
    final socket = await SecureSocket.connect(
      ip,
      6466,
      context: secContext,
      onBadCertificate: (cert) => true,
      timeout: const Duration(seconds: 5),
    );

    socket.listen((data) {
      final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      print('  TV Rx: $hex');
    });

    // Step 1: RemoteConfigure
    final info = [...encodeTag(1, 2), ...encodeVarint(utf8.encode('Smart TV Remote').length), ...utf8.encode('Smart TV Remote')];
    final cfgInner = [...encodeTag(1, 2), ...encodeVarint(info.length), ...info];
    socket.add(wrapWithVarintLength([...encodeTag(1, 2), ...encodeVarint(cfgInner.length), ...cfgInner]));
    await socket.flush();
    await Future.delayed(const Duration(milliseconds: 150));

    // Step 2: RemoteSetActive
    final activeInner = [...encodeTag(1, 0), ...encodeVarint(1)];
    socket.add(wrapWithVarintLength([...encodeTag(2, 2), ...encodeVarint(activeInner.length), ...activeInner]));
    await socket.flush();
    await Future.delayed(const Duration(milliseconds: 150));

    // Step 3: Send HOME (Keycode 3) down -> hold 400ms -> up!
    print('Sending HELD HOME keypress (Keycode 3)... Look at your TV screen!');
    final downInner = [...encodeTag(1, 0), ...encodeVarint(3), ...encodeTag(2, 0), ...encodeVarint(1)];
    socket.add(wrapWithVarintLength([...encodeTag(3, 2), ...encodeVarint(downInner.length), ...downInner]));
    await socket.flush();
    await Future.delayed(const Duration(milliseconds: 400));

    final upInner = [...encodeTag(1, 0), ...encodeVarint(3), ...encodeTag(2, 0), ...encodeVarint(2)];
    socket.add(wrapWithVarintLength([...encodeTag(3, 2), ...encodeVarint(upInner.length), ...upInner]));
    await socket.flush();
    await Future.delayed(const Duration(milliseconds: 500));

    socket.destroy();
    print('Finished sending Held Home keypress.');
  } catch (e) {
    print('  Keycode error: $e');
  }
}
