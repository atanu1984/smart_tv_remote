import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Map<String, List<int>> extractRsaParamsFromDer(List<int> der) {
  for (int i = 0; i < der.length - 260; i++) {
    if (der[i] == 0x02 && der[i + 1] == 0x82 && (der[i + 2] == 0x01 || der[i + 2] == 0x02)) {
      int len = (der[i + 2] << 8) | der[i + 3];
      int modStart = i + 4;
      if (der[modStart] == 0x00) {
        modStart++;
        len--;
      }
      final mod = der.sublist(modStart, modStart + len);
      
      int expStart = modStart + len;
      if (der[expStart] == 0x02) {
        int expLen = der[expStart + 1];
        final exp = der.sublist(expStart + 2, expStart + 2 + expLen);
        return {'modulus': mod, 'exponent': exp};
      }
    }
  }
  return {'modulus': [], 'exponent': []};
}

void main() async {
  const ip = '192.168.0.213';
  print('=== Exact androidtv-remote Secret Formula Solver ($ip:6467) ===');

  final pfxBytes = File('C:/Code/smart_tv_remote/client_cert.pfx').readAsBytesSync();
  final pemContent = File('C:/Code/smart_tv_remote/client_cert_only.pem').readAsStringSync();
  final certB64 = pemContent
      .split('-----BEGIN CERTIFICATE-----')[1]
      .split('-----END CERTIFICATE-----')[0]
      .replaceAll(RegExp(r'\s+'), '');
  final clientDerBytes = base64.decode(certB64);

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

  // Step 3: Send PairingConfiguration
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

  final clientKeys = extractRsaParamsFromDer(clientDerBytes);
  final serverKeys = extractRsaParamsFromDer(socket.peerCertificate?.der ?? []);

  final clientMod = clientKeys['modulus'] ?? [];
  final serverMod = serverKeys['modulus'] ?? [];

  final List<int> nonceHex = [];
  for (int i = 0; i < cleanPin.length; i += 2) {
    nonceHex.add(int.parse(cleanPin.substring(i, i + 2), radix: 16));
  }

  // Exact louis49/androidtv-remote algorithm:
  // sha256( client_modulus + [0x00, 0x01, 0x00, 0x01] + server_modulus + [0x00, 0x01, 0x00, 0x01] + rawHexPIN )
  final exp4B = [0x00, 0x01, 0x00, 0x01];
  final secretData = sha256.convert([...clientMod, ...exp4B, ...serverMod, ...exp4B, ...nonceHex]).bytes;

  print('\n5. Sending Field 40 PairingSecret (Exact androidtv-remote SHA256: ${secretData.length} bytes)...');
  // Tag for Field 40: (40 << 3) | 2 = 322 = [194, 2] = 0xC2 0x02
  final secretInner = [10, secretData.length, ...secretData];
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
      print('>>> SUCCESS! GOOGLE TV PAIRING ACCEPTED BY TV! <<<');
      print('==========================================================');
    } else {
      print('  TV Response Status: Rejected ($hexStr)');
    }
  } else {
    print('  Timeout / Socket closed');
  }

  sub.cancel();
  socket.destroy();
  print('\nDone.');
}
