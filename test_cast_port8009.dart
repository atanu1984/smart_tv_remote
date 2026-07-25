import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  const ip = '192.168.0.213';
  print('=== UNMUTING TV VIA GOOGLE CAST PORT 8009 ($ip:8009) ===');

  try {
    final socket = await SecureSocket.connect(
      ip,
      8009,
      onBadCertificate: (cert) => true,
      timeout: const Duration(seconds: 4),
    );

    print('1. Connected mTLS socket to $ip:8009!');

    socket.listen((data) {
      final str = utf8.decode(data, allowMalformed: true);
      print('  TV Response: $str');
    });

    List<int> encodeSubField(int fieldNumber, List<int> bytes) {
      final tag = (fieldNumber << 3) | 2;
      return [tag, bytes.length, ...bytes];
    }

    List<int> buildCastMessage({
      required String namespace,
      required String destinationId,
      required Map<String, dynamic> payloadJson,
    }) {
      final jsonStr = jsonEncode(payloadJson);
      final jsonBytes = utf8.encode(jsonStr);
      final sourceBytes = utf8.encode('sender-0');
      final destBytes = utf8.encode(destinationId);
      final nsBytes = utf8.encode(namespace);

      final body = <int>[
        8, 0,
        ...encodeSubField(2, sourceBytes),
        ...encodeSubField(3, destBytes),
        ...encodeSubField(4, nsBytes),
        40, 0,
        ...encodeSubField(6, jsonBytes),
      ];

      final len = body.length;
      final lengthHeader = [
        (len >> 24) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF,
      ];

      return [...lengthHeader, ...body];
    }

    // Step 1: Send CONNECT
    print('2. Sending CONNECT to Google Cast receiver-0...');
    final connectMsg = buildCastMessage(
      namespace: 'urn:x-cast:com.google.cast.tp.connection',
      destinationId: 'receiver-0',
      payloadJson: {'type': 'CONNECT'},
    );
    socket.add(connectMsg);
    await socket.flush();
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 2: Send SET_VOLUME UNMUTE (muted: false, level: 0.35)
    print('3. Sending SET_VOLUME { muted: false, level: 0.35 } (UNMUTE)... Listen to your TV!');
    final unmuteMsg = buildCastMessage(
      namespace: 'urn:x-cast:com.google.cast.receiver',
      destinationId: 'receiver-0',
      payloadJson: {
        'type': 'SET_VOLUME',
        'volume': {'level': 0.35, 'muted': false},
        'requestId': 1003,
      },
    );
    socket.add(unmuteMsg);
    await socket.flush();

    await Future.delayed(const Duration(milliseconds: 2000));
    socket.destroy();
    print('\n🎉 Unmute command executed successfully!');
  } catch (e) {
    print('❌ Port 8009 Error: $e');
  }
}
