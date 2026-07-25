import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;

void main() async {
  const ip = '192.168.0.213';
  print('=== DART PAIRING DIAGNOSTIC TEST ($ip:6467) ===');

  // Load client_cert.pfx
  final pfxBytes = File('C:/Code/smart_tv_remote/app_client_cert.pfx').readAsBytesSync();
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

  print('1. Connected mTLS socket to $ip:6467!');

  final List<int> responseBuffer = [];
  socket.listen((data) {
    responseBuffer.addAll(data);
  });

  Future<void> delay(int ms) => Future.delayed(Duration(milliseconds: ms));

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

  // Step 1: Send PairingRequest (field 10)
  print('2. Sending PairingRequest...');
  final serviceName = utf8.encode('atvremote');
  final clientName = utf8.encode('atvremote');
  final reqInner = [
    ...encodeTag(1, 2), ...encodeVarint(serviceName.length), ...serviceName,
    ...encodeTag(2, 2), ...encodeVarint(clientName.length), ...clientName,
  ];
  final reqOuter = [
    ...encodeTag(1, 0), ...encodeVarint(2),
    ...encodeTag(2, 0), ...encodeVarint(200),
    ...encodeTag(10, 2), ...encodeVarint(reqInner.length), ...reqInner,
  ];
  socket.add(wrapWithVarintLength(reqOuter));
  await socket.flush();
  await delay(300);

  // Step 2: Send PairingOption (field 20)
  print('3. Sending PairingOption...');
  final encMsg = [...encodeTag(1, 0), ...encodeVarint(3), ...encodeTag(2, 0), ...encodeVarint(6)];
  final optInner = [
    ...encodeTag(1, 2), ...encodeVarint(encMsg.length), ...encMsg,
    ...encodeTag(2, 2), ...encodeVarint(encMsg.length), ...encMsg,
    ...encodeTag(3, 0), ...encodeVarint(1),
  ];
  final optOuter = [
    ...encodeTag(1, 0), ...encodeVarint(2),
    ...encodeTag(2, 0), ...encodeVarint(200),
    ...encodeTag(20, 2), ...encodeVarint(optInner.length), ...optInner,
  ];
  socket.add(wrapWithVarintLength(optOuter));
  await socket.flush();
  await delay(300);

  // Step 3: Send PairingConfiguration (field 30)
  print('4. Sending PairingConfiguration...');
  final cfgInner = [
    ...encodeTag(1, 2), ...encodeVarint(encMsg.length), ...encMsg,
    ...encodeTag(2, 0), ...encodeVarint(1),
  ];
  final cfgOuter = [
    ...encodeTag(1, 0), ...encodeVarint(2),
    ...encodeTag(2, 0), ...encodeVarint(200),
    ...encodeTag(30, 2), ...encodeVarint(cfgInner.length), ...cfgInner,
  ];
  socket.add(wrapWithVarintLength(cfgOuter));
  await socket.flush();
  await delay(300);

  print('\n==========================================================');
  print('>>> 6-CHARACTER PIN POPUP IS NOW DISPLAYED ON YOUR TV SCREEN! <<<');
  print('==========================================================');
  stdout.write('Type the 6-character PIN code from your TV screen and press ENTER: ');
  final pinInput = stdin.readLineSync() ?? '';
  final cleanPin = pinInput.trim().toUpperCase();

  // Extract client cert modulus and server cert modulus
  final certPem = File('C:/Code/smart_tv_remote/new_client_cert.pem').readAsStringSync();
  final clientCertDer = base64.decode(certPem.replaceAll(RegExp(r'-----[A-Z ]+-----'), '').replaceAll(RegExp(r'\s'), ''));
  final serverCertDer = List<int>.from(socket.peerCertificate?.der ?? []);

  print('\nServer cert DER received from socket: ${serverCertDer.length} bytes');

  // DER modulus extractor
  List<int> extractMod(List<int> der) {
    if (der.isEmpty) return [];
    const rsaOid = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01];
    int oidPos = -1;
    for (int i = 0; i <= der.length - rsaOid.length; i++) {
      bool match = true;
      for (int j = 0; j < rsaOid.length; j++) {
        if (der[i + j] != rsaOid[j]) { match = false; break; }
      }
      if (match) { oidPos = i; break; }
    }
    if (oidPos < 0) return [];
    int bitStringPos = oidPos + 11;
    if (bitStringPos >= der.length || der[bitStringPos] != 0x03) {
      int pos = oidPos + rsaOid.length;
      while (pos < der.length && der[pos] != 0x03) pos++;
      bitStringPos = pos;
    }
    if (bitStringPos >= der.length) return [];
    
    // Read length after tag 0x03
    int pos = bitStringPos + 1;
    int len = der[pos++];
    if (len & 0x80 != 0) {
      final nb = len & 0x7F;
      len = 0;
      for (int k = 0; k < nb; k++) { len = (len << 8) | der[pos++]; }
    }
    int rsaSeqStart = pos + 1; // skip 0x00
    if (rsaSeqStart >= der.length || der[rsaSeqStart] != 0x30) return [];
    
    pos = rsaSeqStart + 1;
    len = der[pos++];
    if (len & 0x80 != 0) {
      final nb = len & 0x7F;
      len = 0;
      for (int k = 0; k < nb; k++) { len = (len << 8) | der[pos++]; }
    }
    int modTagStart = pos;
    if (modTagStart >= der.length || der[modTagStart] != 0x02) return [];
    
    pos = modTagStart + 1;
    len = der[pos++];
    if (len & 0x80 != 0) {
      final nb = len & 0x7F;
      len = 0;
      for (int k = 0; k < nb; k++) { len = (len << 8) | der[pos++]; }
    }
    int mStart = pos;
    var mod = der.sublist(mStart, mStart + len);
    while (mod.isNotEmpty && mod[0] == 0x00) {
      mod = mod.sublist(1);
    }
    return mod;
  }

  final clientMod = extractMod(clientCertDer);
  final serverMod = extractMod(serverCertDer);

  print('Client Modulus: ${clientMod.length} bytes (First 8 bytes: ${clientMod.take(8).map((b)=>b.toRadixString(16).padLeft(2,'0')).join(' ')})');
  print('Server Modulus: ${serverMod.length} bytes (First 8 bytes: ${serverMod.take(8).map((b)=>b.toRadixString(16).padLeft(2,'0')).join(' ')})');

  final pinSliced = cleanPin.length >= 4 ? cleanPin.substring(2) : cleanPin;
  final List<int> pinBytes = [];
  for (int i = 0; i < pinSliced.length; i += 2) {
    pinBytes.add(int.parse(pinSliced.substring(i, i + 2), radix: 16));
  }

  const exp = [0x01, 0x00, 0x01];
  final hashInput = [
    ...clientMod,
    ...exp,
    ...serverMod,
    ...exp,
    ...pinBytes,
  ];

  final digest = crypto.sha256.convert(hashInput);
  final secretBytes = digest.bytes;
  print('Computed Hash (32 bytes): ${secretBytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join(' ').toUpperCase()}');

  // Build PairingSecret payload (field 40)
  final secInner = [
    ...encodeTag(1, 2), ...encodeVarint(secretBytes.length), ...secretBytes,
  ];
  final secOuter = [
    ...encodeTag(1, 0), ...encodeVarint(2),
    ...encodeTag(2, 0), ...encodeVarint(200),
    ...encodeTag(40, 2), ...encodeVarint(secInner.length), ...secInner,
  ];

  responseBuffer.clear();
  socket.add(wrapWithVarintLength(secOuter));
  await socket.flush();

  print('\n5. Sent PairingSecret (Field 40). Waiting for TV response...');
  await delay(1500);

  final hexStr = responseBuffer.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  print('TV Response Hex: $hexStr');

  if (hexStr.contains('C8 01') || hexStr.contains('CA 02')) {
    print('\n🎉🎉🎉 SUCCESS! TV ACCEPTED PIN PAIRING SECRET! 🎉🎉🎉');
  } else {
    print('\n❌ TV REJECTED PIN SECRET: $hexStr');
  }

  socket.destroy();
}
