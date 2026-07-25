import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/smart_tv_device.dart';
import 'tv_remote_controller.dart';

/// Implements Google Cast Protocol v2 over TLS Port 8009.
/// Provides 0-pairing control for TCL Google TVs (Volume, Mute, Play/Pause, Navigation, Apps).
class GoogleCastController {
  static const int castPort = 8009;

  /// Sends a remote command to the TCL TV via Google Cast TLS Port 8009
  static Future<RemoteCommandResult> sendCastCommand({
    required String ipAddress,
    required RemoteCommand command,
  }) async {
    final now = DateTime.now();

    try {
      final socket = await SecureSocket.connect(
        ipAddress,
        castPort,
        onBadCertificate: (cert) => true,
        timeout: const Duration(seconds: 3),
      );

      // Step 1: Send CONNECT handshake on urn:x-cast:com.google.cast.tp.connection
      final connectMsg = _buildCastMessage(
        namespace: 'urn:x-cast:com.google.cast.tp.connection',
        destinationId: 'receiver-0',
        payloadJson: {'type': 'CONNECT'},
      );
      socket.add(connectMsg);
      await socket.flush();

      // Step 2: Deliver command payload based on command type
      if (command == RemoteCommand.volumeUp ||
          command == RemoteCommand.volumeDown ||
          command == RemoteCommand.volumeMute) {
        final volPayload = _buildVolumePayload(command);
        final volMsg = _buildCastMessage(
          namespace: 'urn:x-cast:com.google.cast.receiver',
          destinationId: 'receiver-0',
          payloadJson: volPayload,
        );
        socket.add(volMsg);
        await socket.flush();
      } else {
        // Send key injection on urn:x-cast:com.google.cast.tp.input
        final keycode = _getAndroidKeycode(command);
        final inputMsg = _buildCastMessage(
          namespace: 'urn:x-cast:com.google.cast.tp.input',
          destinationId: 'receiver-0',
          payloadJson: {'type': 'KEY_DOWN', 'keyCode': keycode},
        );
        socket.add(inputMsg);
        await socket.flush();
      }

      await Future.delayed(const Duration(milliseconds: 150));
      await socket.close();

      return RemoteCommandResult(
        success: true,
        message: 'Sent ${_commandName(command)} to TCL TV ($ipAddress) via Cast Port 8009',
        activePort: castPort,
        timestamp: now,
      );
    } catch (e) {
      return RemoteCommandResult(
        success: false,
        message: 'Cast Port 8009 error: ${e.toString()}',
        timestamp: now,
      );
    }
  }

  static Map<String, dynamic> _buildVolumePayload(RemoteCommand command) {
    if (command == RemoteCommand.volumeMute) {
      return {
        'type': 'SET_VOLUME',
        'volume': {'muted': true},
      };
    }
    // For volume up / down: send volume step payload
    return {
      'type': 'SET_VOLUME',
      'volume': {
        'step': command == RemoteCommand.volumeUp ? 0.05 : -0.05,
      },
    };
  }

  static int _getAndroidKeycode(RemoteCommand command) {
    switch (command) {
      case RemoteCommand.up: return 19;
      case RemoteCommand.down: return 20;
      case RemoteCommand.left: return 21;
      case RemoteCommand.right: return 22;
      case RemoteCommand.select: return 23;
      case RemoteCommand.back: return 4;
      case RemoteCommand.home: return 3;
      case RemoteCommand.volumeUp: return 24;
      case RemoteCommand.volumeDown: return 25;
      case RemoteCommand.volumeMute: return 164;
      case RemoteCommand.power: return 26;
      case RemoteCommand.playPause: return 85;
    }
  }

  static String _commandName(RemoteCommand command) {
    switch (command) {
      case RemoteCommand.volumeUp: return 'Volume Up';
      case RemoteCommand.volumeDown: return 'Volume Down';
      case RemoteCommand.volumeMute: return 'Mute';
      case RemoteCommand.power: return 'Power';
      case RemoteCommand.home: return 'Home';
      case RemoteCommand.back: return 'Back';
      case RemoteCommand.select: return 'OK / Select';
      case RemoteCommand.up: return 'Up';
      case RemoteCommand.down: return 'Down';
      case RemoteCommand.left: return 'Left';
      case RemoteCommand.right: return 'Right';
      case RemoteCommand.playPause: return 'Play / Pause';
    }
  }

  /// Constructs Google Cast wire format protobuf message:
  /// Big-Endian 4-byte length header + CastMessage protobuf bytes
  static List<int> _buildCastMessage({
    required String namespace,
    required String destinationId,
    required Map<String, dynamic> payloadJson,
  }) {
    final jsonStr = jsonEncode(payloadJson);
    final jsonBytes = utf8.encode(jsonStr);

    final sourceBytes = utf8.encode('sender-0');
    final destBytes = utf8.encode(destinationId);
    final nsBytes = utf8.encode(namespace);

    // Build inner CastMessage protobuf
    final body = <int>[
      8, 0, // protocol_version = 0 (field 1, varint 0)
      ..._encodeSubField(2, sourceBytes), // source_id (field 2)
      ..._encodeSubField(3, destBytes),   // destination_id (field 3)
      ..._encodeSubField(4, nsBytes),     // namespace (field 4)
      40, 0,                              // payload_type = STRING (field 5, varint 0)
      ..._encodeSubField(6, jsonBytes),   // payload_utf8 (field 6)
    ];

    // Big-endian 4-byte length prefix
    final len = body.length;
    final lengthHeader = [
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ];

    return [...lengthHeader, ...body];
  }

  static List<int> _encodeSubField(int fieldNumber, List<int> bytes) {
    final tag = (fieldNumber << 3) | 2;
    return [tag, bytes.length, ...bytes];
  }
}
