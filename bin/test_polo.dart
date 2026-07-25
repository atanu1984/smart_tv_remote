import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() async {
  const ip = '192.168.0.213';
  print('=== Protocol Version 1 vs Version 2 Polo Solver ($ip:6467) ===');

  final pfxBytes = File('C:/Code/smart_tv_remote/client_cert.pfx').readAsBytesSync();
  final secContext = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(pfxBytes, password: 'temp1234')
    ..usePrivateKeyBytes(pfxBytes, password: 'temp1234');

  Future<Map<String, dynamic>> connectAndHandshake(int protoVersion) async {
    final socket = await SecureSocket.connect(
      ip,
      6467,
      context: secContext,
      onBadCertificate: (cert) => true,
      timeout: const Duration(seconds: 5),
    );

    List<int> responseBuf = [];
    final sub = socket.listen((data) {
      responseBuf.addAll(data);
    });

    Future<List<int>> readMsg() async {
      final start = DateTime.now();
      while (DateTime.now().difference(start) < const Duration(milliseconds: 2500)) {
        if (responseBuf.isNotEmpty) {
          final msgLen = responseBuf[0];
          if (responseBuf.length >= msgLen + 1) {
            final msg = responseBuf.sublist(0, msgLen + 1);
            responseBuf.removeRange(0, msgLen + 1);
            return msg;
          }
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      final remaining = List<int>.from(responseBuf);
      responseBuf.clear();
      return remaining;
    }

    // Step 1: Send PairingRequest (field 10)
    final s = utf8.encode('androidtvremote2');
    final c = utf8.encode('Smart TV Remote');
    final reqInner = [10, s.length, ...s, 18, c.length, ...c];
    final reqOuter = [8, protoVersion, 16, 200, 1, 82, reqInner.length, ...reqInner];
    socket.add([reqOuter.length, ...reqOuter]);
    await socket.flush();
    await readMsg();

    // Step 2: Send PairingOption (field 20 - Tag 0xA2 0x01)
    final encodingMsg = [8, 3, 16, 6];
    final optInner = [10, encodingMsg.length, ...encodingMsg, 18, encodingMsg.length, ...encodingMsg, 24, 1];
    final optOuter = [8, protoVersion, 16, 200, 1, 162, 1, optInner.length, ...optInner];
    socket.add([optOuter.length, ...optOuter]);
    await socket.flush();
    await readMsg();

    // Step 3: Send PairingConfiguration (field 30 - Tag 0xF2 0x01)
    final cfgInner = [10, encodingMsg.length, ...encodingMsg, 16, 1];
    final cfgOuter = [8, protoVersion, 16, 200, 1, 242, 1, cfgInner.length, ...cfgInner];
    socket.add([cfgOuter.length, ...cfgOuter]);
    await socket.flush();
    await readMsg();

    return {
      'socket': socket,
      'sub': sub,
      'serverCert': socket.peerCertificate,
      'readMsg': readMsg,
      'protoVersion': protoVersion,
    };
  }

  // Connect with v2
  final sess = await connectAndHandshake(2);
  print('\n==========================================================');
  print('>>> V1 6-CHARACTER PIN POPUP IS NOW DISPLAYED ON YOUR TV SCREEN! <<<');
  print('==========================================================');
  stdout.write('Type the 6-character PIN code from your TV screen and press ENTER: ');
  final pinInput = stdin.readLineSync() ?? '';
  final cleanPin = pinInput.trim().replaceAll('-', '').toUpperCase();

  final List<int> pinHex = [];
  for (int i = 0; i < cleanPin.length; i += 2) {
    pinHex.add(int.parse(cleanPin.substring(i, i + 2), radix: 16));
  }
  final pinAscii = utf8.encode(cleanPin);

  final candidates = [
    {'name': 'V1 Raw Hex Bytes [0x12, 0x34, 0x56]', 'data': pinHex},
    {'name': 'V1 Raw ASCII Bytes "123456"', 'data': pinAscii},
    {'name': 'V1 SHA256(ServerDer + HexPIN)', 'data': sha256.convert([...(sess['serverCert'] as X509Certificate).der, ...pinHex]).bytes},
    {'name': 'V1 SHA256(ServerDer + AsciiPIN)', 'data': sha256.convert([...(sess['serverCert'] as X509Certificate).der, ...pinAscii]).bytes},
  ];

  Map<String, dynamic> currentSession = sess;

  for (int idx = 0; idx < candidates.length; idx++) {
    final cand = candidates[idx];
    final name = cand['name'] as String;
    final secretData = cand['data'] as List<int>;

    if (idx > 0) {
      try { (currentSession['socket'] as SecureSocket).destroy(); } catch (_) {}
      try {
        currentSession = await connectAndHandshake(2);
      } catch (e) {
        print('  Failed to reconnect: $e');
        continue;
      }
    }

    final sock = currentSession['socket'] as SecureSocket;
    final readFn = currentSession['readMsg'] as Future<List<int>> Function();

    print('\nTesting $name (${secretData.length} bytes)...');
    final inner = [10, secretData.length, ...secretData];
    final outer = [8, 1, 16, 200, 1, 162, 2, inner.length, ...inner];
    sock.add([outer.length, ...outer]);
    await sock.flush();

    final resp = await readFn();
    if (resp.isNotEmpty) {
      final hexStr = resp.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      print('  TV Response: $hexStr');
      if (hexStr.contains('10 C8 01') || hexStr.contains('AA 02') || hexStr.contains('10 08 01')) {
        print('\n==========================================================');
        print('>>> MATCH SUCCESSFUL! V1 PAIRING ACCEPTED BY TV: $name <<<');
        print('==========================================================');
        break;
      } else {
        print('  Rejected: $hexStr');
      }
    } else {
      print('  Timeout / Socket closed');
    }
  }

  try { (currentSession['socket'] as SecureSocket).destroy(); } catch (_) {}
  print('\nDone.');
}
