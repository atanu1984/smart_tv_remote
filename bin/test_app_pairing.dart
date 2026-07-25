import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() async {
  const ip = '192.168.0.213';
  print('=== Testing Exact App Pairing Secret (Field 40: 0xC2 0x02) ($ip:6467) ===');

  final pfxBytes = File('C:/Code/smart_tv_remote/client_cert.pfx').readAsBytesSync();
  final secContext = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(pfxBytes, password: 'temp1234')
    ..usePrivateKeyBytes(pfxBytes, password: 'temp1234');

  final socket = await SecureSocket.connect(
    ip,
    6467,
    context: secContext,
    onBadCertificate: (cert) => true,
    timeout: const Duration(seconds: 5),
  );

  print('1. Connected mTLS socket to $ip:6467 with CN=atvremote cert!');

  final List<int> responseBuffer = [];
  final sub = socket.listen((data) {
    responseBuffer.addAll(data);
  });

  Future<List<int>> readMsg() async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < const Duration(milliseconds: 2500)) {
      if (responseBuffer.isNotEmpty) {
        final msgLen = responseBuffer[0];
        if (responseBuffer.length >= msgLen + 1) {
          final msg = responseBuffer.sublist(0, msgLen + 1);
          responseBuffer.removeRange(0, msgLen + 1);
          return msg;
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final remaining = List<int>.from(responseBuffer);
    responseBuffer.clear();
    return remaining;
  }

  // Step 1: Send PairingRequest
  print('2. Sending PairingRequest...');
  final s = utf8.encode('androidtvremote2');
  final c = utf8.encode('Smart TV Remote');
  final reqInner = [10, s.length, ...s, 18, c.length, ...c];
  final reqOuter = [8, 2, 16, 200, 1, 82, reqInner.length, ...reqInner];
  socket.add([reqOuter.length, ...reqOuter]);
  await socket.flush();
  await readMsg();

  // Step 2: Send PairingOption
  print('3. Sending PairingOption...');
  final encodingMsg = [8, 3, 16, 6];
  final optInner = [10, encodingMsg.length, ...encodingMsg, 18, encodingMsg.length, ...encodingMsg, 24, 1];
  final optOuter = [8, 2, 16, 200, 1, 162, 1, optInner.length, ...optInner];
  socket.add([optOuter.length, ...optOuter]);
  await socket.flush();
  await readMsg();

  // Step 3: Send PairingConfiguration — triggers TV PIN popup
  print('4. Sending PairingConfiguration...');
  final cfgInner = [10, encodingMsg.length, ...encodingMsg, 16, 1];
  final cfgOuter = [8, 2, 16, 200, 1, 242, 1, cfgInner.length, ...cfgInner];
  socket.add([cfgOuter.length, ...cfgOuter]);
  await socket.flush();
  await readMsg();

  print('\n==========================================================');
  print('>>> 6-CHARACTER PIN POPUP IS NOW DISPLAYED ON YOUR TV SCREEN! <<<');
  print('==========================================================');
  stdout.write('Type the 6-character PIN code from your TV screen and press ENTER: ');
  final pinInput = stdin.readLineSync() ?? '';
  final cleanPin = pinInput.trim().replaceAll('-', '').toUpperCase();

  // Decode Nonce (3 raw hex bytes or 6 ascii bytes)
  final List<int> nonceHex = [];
  for (int i = 0; i < cleanPin.length; i += 2) {
    nonceHex.add(int.parse(cleanPin.substring(i, i + 2), radix: 16));
  }
  final nonceAscii = utf8.encode(cleanPin);

  print('\n5. Sending Field 40 PairingSecret (Raw Hex Bytes: ${nonceHex.length} bytes)...');
  // Tag for Field 40 (PairingSecret): (40 << 3) | 2 = 322 = 194 (0xC2), 2 (0x02) -> [194, 2]
  final secretInner = [10, nonceHex.length, ...nonceHex];
  final secretOuter = [8, 2, 16, 200, 1, 194, 2, secretInner.length, ...secretInner];
  
  responseBuffer.clear();
  socket.add([secretOuter.length, ...secretOuter]);
  await socket.flush();

  await Future.delayed(const Duration(milliseconds: 1500));

  if (responseBuffer.isNotEmpty) {
    final hexStr = responseBuffer.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    print('  TV Response: $hexStr');
    if (hexStr.contains('C8 01') || hexStr.contains('AA 02') || hexStr.contains('10 08 02')) {
      print('\n==========================================================');
      print('>>> SUCCESS! GOOGLE TV ACCEPTED FIELD 40 PAIRING SECRET! <<<');
      print('==========================================================');
    } else {
      print('  TV Response Status: Rejected ($hexStr)');
    }
  } else {
    print('  Timeout / Socket closed');
  }

  sub.cancel();
  socket.destroy();
  print('\nDone testing.');
}
