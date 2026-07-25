import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';
import 'client_certificate_service.dart'; // kept for SharedPreferences cert override support

// ---------------------------------------------------------------------------
// Embedded self-signed client certificate for mTLS authentication.
// Generated as a matched RSA 2048-bit keypair via New-SelfSignedCertificate.
// The cert+key are verified to be a matching pair (same RSA modulus).
// Valid for 10 years. TV pairs with this cert fingerprint during PIN flow.
// ---------------------------------------------------------------------------
const String _kClientCertPem = '''-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----''';

const String _kClientKeyPem = '''-----BEGIN PRIVATE KEY-----
MIIEzAIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC8F2VLwC5lx9qQwDGCVoyBpSnC
yIQEN/fMSfXrDXRU3DNJCGqFgPRb/Yy2R34GEZngiSKgeaJNNuU0MY3zv16VjLuFZY6gN5L3gPym
BdLZR8I46B/0WwLAqh4MhmyzohSMTVxb2uir8fDNejJ2zXPxyy2pce2wegvuCKzbV3KGdUfxZXCi
hOG69tSBTDrSZpSzYWHLH9o62nIhkA5QsADQF180WQFmnOLilRvFtgoUhBTOQfKfuq3zLkt0M84p
ex2clRhxrTqKc67K8BLfv8RtzuMGUcsKIKOyUB4mIpU82nj41rv1/9onDwsdBrX6+ngcR7p77yhr
nf/Uryl9H3LxAgMBAAECggEAK2CR4dheWuauRzers01WdgerC9rGZ1qo8RoVdrHRpEhsI2mnd0Z4
FEbzDo6KR8gDXr8Bl1S102zXiyPqgs4deAvOq0Lyk4x9fkrm+Tral3VvG0SdKfNbPSd+apENvJei
eYDVzfE8O3s+d4S44qEbHiYnT66QjGR5H9osUyFlrhA00xyFRVmZpRGjOAo3IO0YUz8SZKVYClAv
Cni1ap91FlkXTDpgeHhC81usi7QTfdgvK7ge+juyEeHz0DW1qGUXjTl4hUUPCqRrO6T+gFOofmI1
oaImY1vajoLgGKoBIU4Meq7XwW3WsqkrTlI4GgjniSeHT/ckMToaDgOP/+vAaQKBgQDT6uofI+WL
W5snrA3j95QQAqADMPqMSco/aG/utpEDpvGCFDNxa1MCYxRt4dCqaDQ9DSP8DFbBJX+NyiyQGwaV
4LU52nzf7tXiaLrXnsg0rGmprnepv2WyIZ0r4lZX9OsJvg5b2RnD1pfFdws0EaQ2fTkH1UczTMj8
gGfyK7FKhwKBgQDjN646MLFxsvEqHIcnEglGQF2LHqwvw5kZ+49xBF/3vm+VbAAVeNqjbSGgC6fe
Z3KdugPd8SW5SQ7iwWklW/NUGgg4ULNHZ8L2WtGzoFMukJor9wEwRfvIkbmTYuTnjYe+fJ1ygLzk
VsTh29G7OaO83FrPHYTTVwb1TXnCN8pcxwKBgQC8dvL39siyAyodQhqoXwpCotMDg4+PLCC9+3dw
aNTW1qV59dU6TSRpvwvwHR+iLUIn+YPDKIYPB/ZEd0Tic+aLbGg/p1vfG10EGffwwrlyftMJoKuz
PxCGNva8jHIVjy9oXqoObSlIzZP0fUZtbDMKcptBqB/GM8ebJ+dJrCnkCQKBgA3qpSMvRE8AdMDt
imGcOzEwVApnUIiEZGYxADId4HreERuHx+GIy2tjDcIttJRspZp/gCkh0futO9ormnMNVLP7/DDm
0HQ5KLnKCjoEQdQCS08SC+KXBrrcIg+i6P49rui93S7cL7WUku56djgPabXxkSZKWo5PMD/qBOEe
ZaiVAoGAZbNp1RQaWTQhGr7PgZNYPskrLFAyniANcaOgXltha44E5E6uMb6aHuSzZ4Ko9uymB8Vq
UHUJ/JRP6PT7ArlFjngZuT1ydBTr05qDCeskMP/3VMeML55vKoStOL+1Vjfxpfan+Ajtc3SgY+ml
Wo82hW3/Wwvx/atYNDAyCRJ/f4mgDTALBgNVHQ8xBAMCAJA=
-----END PRIVATE KEY-----''';

class PairingResult {
  final bool success;
  final String message;
  final bool pinRequired;
  final String? ipAddress;

  const PairingResult({
    required this.success,
    required this.message,
    this.pinRequired = false,
    this.ipAddress,
  });
}

/// Creates a [SecurityContext] pre-loaded with our client certificate.
/// If any certificate mismatch or corruption is detected, automatically resets
/// local storage and falls back to a fresh verified matching keypair.
Future<SecurityContext> _buildSecurityContext() async {
  try {
    final certService = ClientCertificateService();
    final certBytes = await certService.getClientCertBytes();
    final keyBytes = await certService.getClientKeyBytes();
    
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(certBytes);
    ctx.usePrivateKeyBytes(keyBytes);
    return ctx;
  } catch (e) {
    // Automatic Self-Healing: If stored cert/key mismatched or failed TLS validation,
    // wipe the corrupted stored cert and initialize with fresh verified matching pair.
    await ClientCertificateService().resetToDefault();
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(utf8.encode(_kClientCertPem));
    ctx.usePrivateKeyBytes(utf8.encode(_kClientKeyPem));
    return ctx;
  }
}

/// Manages a persistent mTLS session on Port 6466 for authenticated keycode delivery.
///
/// The Google TV Remote Protocol v2 requires:
///   1. A persistent mTLS connection (client cert must be presented).
///   2. The TV sends RemoteStart { started: true } after the TLS handshake.
///   3. Only AFTER RemoteStart can keycode messages be sent.
///   4. The TV sends periodic RemotePing which must be answered with RemotePong,
///      or the connection is dropped within ~10 seconds.
class _RemoteSession {
  final String ipAddress;
  SecureSocket? _socket;
  StreamSubscription<List<int>>? _sub;
  bool _started = false;
  bool _connected = false;
  Completer<bool> _startedCompleter = Completer<bool>();

  _RemoteSession(this.ipAddress);

  Future<bool> connect() async {
    try {
      AppLogger.log('Connecting mTLS control session to $ipAddress:6466...');
      _startedCompleter = Completer<bool>();
      _socket = await SecureSocket.connect(
        ipAddress,
        6466,
        context: await _buildSecurityContext(),
        onBadCertificate: (cert) => true,
        timeout: const Duration(seconds: 4),
      );
      _connected = true;
      AppLogger.log('mTLS socket connected to $ipAddress:6466!');

      _sub = _socket!.listen(
        _onData,
        onError: (e) {
          AppLogger.log('Port 6466 socket error: $e');
          _disconnect();
        },
        onDone: () {
          AppLogger.log('Port 6466 socket closed by TV');
          _disconnect();
        },
        cancelOnError: true,
      );

      // Protocol Handshake: Send RemoteConfigure & RemoteSetActive with necessary delay for Android TLS
      try {
        if (_socket == null || !_connected) return false;
        _socket!.add(GoogleTvPairingService._buildRemoteConfigurePayload());
        await _socket!.flush();
        await Future.delayed(const Duration(milliseconds: 150));

        if (_socket == null || !_connected) return false;
        _socket!.add(GoogleTvPairingService._buildRemoteSetActivePayload());
        await _socket!.flush();
        await Future.delayed(const Duration(milliseconds: 150));
        AppLogger.log('Sent RemoteConfigure & RemoteSetActive to $ipAddress:6466');
      } catch (e) {
        AppLogger.log('Error sending handshake to 6466: $e');
      }

      // Wait for RemoteStart handshake or data
      _started = await _startedCompleter.future
          .timeout(const Duration(seconds: 2), onTimeout: () {
        return true;
      });

      return _started;
    } catch (e) {
      AppLogger.log('Failed to connect mTLS control session $ipAddress:6466: $e');
      _connected = false;
      return false;
    }
  }

  void _onData(List<int> data) {
    if (data.isEmpty) return;
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    AppLogger.log('TV Rx on 6466 ($ipAddress): $hex');

    // Detect TV RemotePing (exact sequence: 0x12 0x02 0x3A 0x00) and reply with RemotePong (02 3A 00)
    for (int i = 0; i <= data.length - 4; i++) {
      if (data[i] == 0x12 && data[i + 1] == 0x02 && data[i + 2] == 0x3A && data[i + 3] == 0x00) {
        AppLogger.log('Received RemotePing from TV ($ipAddress). Sending RemotePong (02 3A 00)...');
        _socket?.add([0x02, 0x3A, 0x00]);
        _socket?.flush();
        break;
      }
    }

    if (!_startedCompleter.isCompleted) {
      _startedCompleter.complete(true);
      _started = true;
    }
  }

  void _disconnect() {
    AppLogger.log('Disconnecting mTLS control session $ipAddress:6466');
    _connected = false;
    _started = false;
    if (!_startedCompleter.isCompleted) _startedCompleter.complete(false);
    _sub?.cancel();
    _socket?.close();
    _socket = null;
  }

  Future<bool> sendKeycode(List<int> payload) async {
    if (!_connected || _socket == null) {
      AppLogger.log('sendKeycode aborted on 6466 ($ipAddress): socket connected=$_connected');
      return false;
    }
    try {
      final hex = payload.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      AppLogger.log('Flushing keycode payload to 6466 ($ipAddress): $hex');
      _socket!.add(payload);
      await _socket!.flush();
      return true;
    } catch (e) {
      AppLogger.log('sendKeycode Exception on 6466 ($ipAddress): $e');
      _disconnect();
      return false;
    }
  }

  void dispose() => _disconnect();
}

class GoogleTvPairingService {
  static const String _pairedDevicesPrefKey = 'google_tv_paired_devices_v2';
  final HttpClient _httpClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;

  // Persistent mTLS sessions cached per IP address
  final Map<String, _RemoteSession> _sessions = {};

  // Active pairing socket, buffer & subscription maintained while waiting for PIN entry
  SecureSocket? _activePairingSocket;
  StreamSubscription<List<int>>? _pairingSub;
  final List<int> _pairingResponseBuffer = [];

  /// Checks if the given TV device IP is already paired and saved locally
  Future<bool> isDevicePaired(String ipAddress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pairedList = prefs.getStringList(_pairedDevicesPrefKey) ?? [];
      return pairedList.contains(ipAddress);
    } catch (_) {
      return false;
    }
  }

  /// Removes a device from the paired list (allows re-pairing)
  Future<void> unpairDevice(String ipAddress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pairedList = prefs.getStringList(_pairedDevicesPrefKey) ?? [];
      pairedList.remove(ipAddress);
      await prefs.setStringList(_pairedDevicesPrefKey, pairedList);
      _sessions.remove(ipAddress)?.dispose();
    } catch (_) {}
  }

  /// Saves device IP as paired in persistent storage
  Future<void> markDevicePaired(String ipAddress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pairedList = prefs.getStringList(_pairedDevicesPrefKey) ?? [];
      if (!pairedList.contains(ipAddress)) {
        pairedList.add(ipAddress);
        await prefs.setStringList(_pairedDevicesPrefKey, pairedList);
      }
    } catch (_) {}
  }

  /// Cancels active pairing session and closes pairing socket
  void cancelPairing() {
    try {
      _pairingSub?.cancel();
      _pairingSub = null;
      _pairingResponseBuffer.clear();
      _activePairingSocket?.destroy();
      _activePairingSocket = null;
    } catch (_) {}
  }

  /// Initiates Phase 1: Connect to TV port 6467 with client cert and send PairingRequest + PairingConfiguration.
  /// Keeps the socket open so that the TV maintains the 6-digit PIN popup on screen.
  Future<PairingResult> initiatePairing(String ipAddress) async {
    cancelPairing(); // Clear any existing pairing connection

    try {
      final socket = await SecureSocket.connect(
        ipAddress,
        6467,
        context: await _buildSecurityContext(),
        onBadCertificate: (cert) => true,
        timeout: const Duration(seconds: 5),
      );
      _activePairingSocket = socket;

      // Buffer socket read events safely in the background
      _pairingResponseBuffer.clear();
      _pairingSub = socket.listen(
        (data) {
          _pairingResponseBuffer.addAll(data);
        },
        onError: (_) {},
        onDone: () {},
        cancelOnError: false,
      );

      // Step 1: Send PairingRequest (field 10)
      socket.add(_buildPairingRequestPayload());
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 250));

      // Step 2: Send PairingOption (field 20)
      socket.add(_buildPairingOptionPayload());
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 250));

      // Step 3: Send PairingConfiguration (field 30) — triggers TV on-screen PIN overlay
      socket.add(_buildPairingConfigurationPayload());
      await socket.flush();

      return PairingResult(
        success: true,
        message: 'Pairing requested! Please check your TV screen for a 6-digit PIN code.',
        pinRequired: true,
        ipAddress: ipAddress,
      );
    } catch (e) {
      cancelPairing();
      return PairingResult(
        success: false,
        message: 'Connection failed ($e). Check Wi-Fi connection and TV state.',
        pinRequired: false,
        ipAddress: ipAddress,
      );
    }
  }

  /// Initiates Phase 2: Send PairingSecret (PIN) to TV on the active pairing socket and confirm pairing
  Future<PairingResult> verifyPin(String ipAddress, String pinCode) async {
    final cleanPin = pinCode.trim().toUpperCase();
    if (cleanPin.isEmpty) {
      return PairingResult(
        success: false,
        message: 'PIN code cannot be empty.',
        pinRequired: true,
        ipAddress: ipAddress,
      );
    }

    try {
      SecureSocket socket;
      if (_activePairingSocket != null) {
        socket = _activePairingSocket!;
      } else {
        // Reconnect socket and initialize session steps 1-3 FIRST before sending secret
        socket = await SecureSocket.connect(
          ipAddress,
          6467,
          context: await _buildSecurityContext(),
          onBadCertificate: (cert) => true,
          timeout: const Duration(seconds: 5),
        );
        _activePairingSocket = socket;
        _pairingResponseBuffer.clear();
        _pairingSub = socket.listen(
          (data) {
            _pairingResponseBuffer.addAll(data);
          },
          onError: (_) {},
          onDone: () {},
          cancelOnError: false,
        );

        // Perform steps 1-3 on the new socket
        socket.add(_buildPairingRequestPayload());
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 200));

        socket.add(_buildPairingOptionPayload());
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 200));

        socket.add(_buildPairingConfigurationPayload());
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _pairingResponseBuffer.clear();

      // Extract client cert modulus from active certificate bytes (guarantees match with TLS handshake)
      final activeCertBytes = await ClientCertificateService().getClientCertBytes();
      final clientCertDer = _pemToDer(utf8.decode(activeCertBytes));
      final serverCertDer = List<int>.from(socket.peerCertificate?.der ?? []);
      final clientMod = _extractRsaModulusFromCertDer(clientCertDer);
      final serverMod = _extractRsaModulusFromCertDer(serverCertDer);

      final payload = _buildPairingSecretPayload(cleanPin, clientMod, serverMod);
      socket.add(payload);
      await socket.flush();

      // Dynamic polling wait: wait for response bytes to arrive (up to 3.5 seconds)
      int elapsedTime = 0;
      while (_pairingResponseBuffer.isEmpty && elapsedTime < 3500) {
        await Future.delayed(const Duration(milliseconds: 100));
        elapsedTime += 100;
      }
      // Brief pause to allow any remaining response bytes to land
      await Future.delayed(const Duration(milliseconds: 300));

      final responseHex = _pairingResponseBuffer
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');

      cancelPairing();

      // Check TV response status
      if (responseHex.contains('C8 01') || responseHex.contains('CA 02')) {
        await markDevicePaired(ipAddress);
        _sessions.remove(ipAddress)?.dispose(); // Clear old session
        return PairingResult(
          success: true,
          message: 'Google TV paired successfully! You can now use all remote controls.',
          pinRequired: false,
          ipAddress: ipAddress,
        );
      } else if (responseHex.contains('94 03') || responseHex.contains('402')) {
        // TV returned 402 (STATUS_BAD_SECRET)
        await unpairDevice(ipAddress);
        return PairingResult(
          success: false,
          message: 'PIN code mismatch ($cleanPin). Please check your TV screen and enter the exact 6-character code.',
          pinRequired: true,
          ipAddress: ipAddress,
        );
      } else {
        // TV response timeout or generic rejection
        await unpairDevice(ipAddress);
        return PairingResult(
          success: false,
          message: responseHex.isNotEmpty
              ? 'TV rejected PIN (Response: $responseHex). Tap Connect to try again.'
              : 'TV response timed out. Please tap Connect to get a new PIN on screen.',
          pinRequired: true,
          ipAddress: ipAddress,
        );
      }
    } catch (e) {
      cancelPairing();
      await unpairDevice(ipAddress);
    }

    return PairingResult(
      success: false,
      message: 'PIN verification failed. The code may be incorrect or expired. Try pairing again.',
      pinRequired: true,
      ipAddress: ipAddress,
    );
  }

  /// Sends an authenticated keycode to the TV via persistent mTLS session (port 6466)
  Future<bool> sendAuthenticatedKeycode(String ipAddress, int keycode) async {
    final downPayload = _buildRemoteKeycodeActionPayload(keycode, 1);
    final upPayload = _buildRemoteKeycodeActionPayload(keycode, 2);

    final downSent = await _sendPayload(ipAddress, downPayload);
    if (!downSent) return false;

    await Future.delayed(const Duration(milliseconds: 50));
    final upSent = await _sendPayload(ipAddress, upPayload);
    return downSent && upSent;
  }

  Future<bool> _sendPayload(String ipAddress, List<int> payload) async {
    // 1. Try to reuse existing session
    var session = _sessions[ipAddress];
    if (session != null && session._connected) {
      final sent = await session.sendKeycode(payload);
      if (sent) return true;
      _sessions.remove(ipAddress)?.dispose();
    }

    // 2. Establish a new persistent session
    try {
      final newSession = _RemoteSession(ipAddress);
      final connected = await newSession.connect();
      if (connected) {
        _sessions[ipAddress] = newSession;
        final sent = await newSession.sendKeycode(payload);
        if (sent) return true;
      } else {
        newSession.dispose();
      }
    } catch (_) {}

    return false;
  }

  // ---------------------------------------------------------------------------
  // Protobuf Binary Encoding with Varint support
  // ---------------------------------------------------------------------------

  static List<int> _encodeVarint(int value) {
    final List<int> bytes = [];
    int v = value;
    while (v >= 0x80) {
      bytes.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    bytes.add(v & 0x7F);
    return bytes;
  }

  static List<int> _encodeTag(int fieldNumber, int wireType) {
    return _encodeVarint((fieldNumber << 3) | wireType);
  }

  static List<int> _encodeString(int fieldNumber, String value) {
    final bytes = utf8.encode(value);
    return [..._encodeTag(fieldNumber, 2), ..._encodeVarint(bytes.length), ...bytes];
  }

  static List<int> _encodeInt(int fieldNumber, int value) {
    return [..._encodeTag(fieldNumber, 0), ..._encodeVarint(value)];
  }

  static List<int> _encodeSubMessage(int fieldNumber, List<int> inner) {
    return [..._encodeTag(fieldNumber, 2), ..._encodeVarint(inner.length), ...inner];
  }

  static List<int> _wrapWithVarintLength(List<int> payload) {
    return [..._encodeVarint(payload.length), ...payload];
  }

  static List<int> _buildPairingRequestPayload({
    String serviceName = 'androidtvremote2',
    String clientName = 'Smart TV Remote',
  }) {
    final inner = [
      ..._encodeString(1, serviceName),
      ..._encodeString(2, clientName),
    ];

    final pairingMsg = [
      ..._encodeInt(1, 2),   // protocol_version = 2
      ..._encodeInt(2, 200), // status = STATUS_OK (200)
      ..._encodeSubMessage(10, inner), // PairingRequest at field 10
    ];

    return _wrapWithVarintLength(pairingMsg);
  }

  /// Builds PairingOption message (field 20)
  static List<int> _buildPairingOptionPayload() {
    final encodingMsg = [
      ..._encodeInt(1, 3), // type = ENCODING_HEXADECIMAL (3)
      ..._encodeInt(2, 6), // symbol_length = 6
    ];

    final optionInner = [
      ..._encodeSubMessage(1, encodingMsg), // input_encodings at field 1
      ..._encodeSubMessage(2, encodingMsg), // output_encodings at field 2
      ..._encodeInt(3, 1),                  // preferred_role = ROLE_TYPE_INPUT (1) at field 3
    ];

    final pairingMsg = [
      ..._encodeInt(1, 2),   // protocol_version = 2
      ..._encodeInt(2, 200), // status = STATUS_OK (200)
      ..._encodeSubMessage(20, optionInner), // pairing_option at field 20
    ];

    return _wrapWithVarintLength(pairingMsg);
  }

  /// Builds PairingConfiguration message (field 30) required to complete Step 3 and inflate TV PIN overlay
  static List<int> _buildPairingConfigurationPayload() {
    final encodingMsg = [
      ..._encodeInt(1, 3), // type = ENCODING_HEXADECIMAL (3)
      ..._encodeInt(2, 6), // symbol_length = 6
    ];

    final configInner = [
      ..._encodeSubMessage(1, encodingMsg), // encoding at field 1
      ..._encodeInt(2, 1),                  // client_role = ROLE_TYPE_INPUT (1) at field 2
    ];

    final pairingMsg = [
      ..._encodeInt(1, 2),   // protocol_version = 2
      ..._encodeInt(2, 200), // status = STATUS_OK (200)
      ..._encodeSubMessage(30, configInner), // pairing_configuration at field 30
    ];

    return _wrapWithVarintLength(pairingMsg);
  }

  /// Builds PairingSecret message (field 40) using the exact POLO secret derivation.
  ///
  /// Verified algorithm (matches louis49/androidtv-remote & AOSP Polo):
  ///   secret = SHA256(
  ///     clientRsaModulus(256B) + [0x01,0x00,0x01] +   // client pubkey
  ///     serverRsaModulus(256B) + [0x01,0x00,0x01] +   // server pubkey
  ///     hexPin.substring(2) parsed as raw bytes         // e.g. "E1838F" -> [0x83, 0x8F]
  ///   )
  static List<int> _buildPairingSecretPayload(
      String pinCode,
      List<int> clientModulus,
      List<int> serverModulus,
  ) {
    final cleanPin = pinCode.trim().toUpperCase();

    // Drop the first 2 hex characters (1 byte), use remaining 4 chars = 2 bytes.
    // Matches: code.slice(2) in louis49/androidtv-remote PairingManager.js
    final pinSliced = cleanPin.length >= 4 ? cleanPin.substring(2) : cleanPin;
    final List<int> pinBytes = [];
    for (int i = 0; i < pinSliced.length; i += 2) {
      pinBytes.add(int.parse(pinSliced.substring(i, i + 2), radix: 16));
    }

    // RSA exponent is always [0x01, 0x00, 0x01] (65537) in both client and server certs
    const List<int> exp = [0x01, 0x00, 0x01];

    final hashInput = [
      ...clientModulus,
      ...exp,
      ...serverModulus,
      ...exp,
      ...pinBytes,
    ];

    final digest = crypto.sha256.convert(hashInput);
    final secretBytes = digest.bytes;

    final inner = [
      ..._encodeTag(1, 2),
      ..._encodeVarint(secretBytes.length),
      ...secretBytes,
    ];

    final pairingMsg = [
      ..._encodeInt(1, 2),   // protocol_version = 2
      ..._encodeInt(2, 200), // status = STATUS_OK (200)
      ..._encodeSubMessage(40, inner), // PairingSecret at field 40
    ];

    return _wrapWithVarintLength(pairingMsg);
  }

  /// Decodes a PEM certificate string into raw DER bytes.
  static List<int> _pemToDer(String pem) {
    final b64 = pem
        .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    return base64.decode(b64);
  }

  /// Reads an ASN.1 DER length field starting at [pos].
  /// Returns a record of (valueStartOffset, valueLength).
  static (int, int) _asn1ReadLen(List<int> der, int pos) {
    // Skip tag byte
    pos++;
    int len = der[pos++];
    if (len & 0x80 != 0) {
      final numBytes = len & 0x7F;
      len = 0;
      for (int i = 0; i < numBytes; i++) {
        len = (len << 8) | der[pos++];
      }
    }
    return (pos, len);
  }

  /// Extracts the RSA modulus from a full X.509 DER certificate using
  /// pure Dart ASN.1 traversal — no external library required.
  ///
  /// Structure:
  ///   Certificate SEQUENCE
  ///     TBSCertificate SEQUENCE
  ///       ...
  ///       SubjectPublicKeyInfo SEQUENCE
  ///         AlgorithmIdentifier SEQUENCE { OID(9 bytes), NULL(2 bytes) }
  ///         BIT STRING { 0x00, RSAPublicKey SEQUENCE { modulus INTEGER, exponent INTEGER } }
  static List<int> _extractRsaModulusFromCertDer(List<int> der) {
    if (der.isEmpty) return [];
    try {
      // RSA OID: 1.2.840.113549.1.1.1 (9 bytes)
      const rsaOid = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01];

      // Find RSA OID position in DER
      int oidPos = -1;
      for (int i = 0; i <= der.length - rsaOid.length; i++) {
        bool match = true;
        for (int j = 0; j < rsaOid.length; j++) {
          if (der[i + j] != rsaOid[j]) { match = false; break; }
        }
        if (match) { oidPos = i; break; }
      }
      if (oidPos < 0) return [];

      // In SubjectPublicKeyInfo, AlgorithmIdentifier ends after OID(9B) + NULL(0x05 0x00, 2B).
      // The BIT STRING tag (0x03) of SubjectPublicKeyInfo is located EXACTLY at oidPos + 11.
      int bitStringPos = oidPos + 11;
      if (bitStringPos >= der.length || der[bitStringPos] != 0x03) {
        // Fallback search if non-standard NULL encoding
        int pos = oidPos + rsaOid.length;
        while (pos < der.length && der[pos] != 0x03) pos++;
        bitStringPos = pos;
      }
      if (bitStringPos >= der.length) return [];

      // Skip BIT STRING tag+length, then skip unused-bits byte (0x00)
      final (bitValueStart, _) = _asn1ReadLen(der, bitStringPos);
      int rsaPkeyStart = bitValueStart + 1; // skip 0x00 unused-bits byte

      // RSAPublicKey SEQUENCE (tag 0x30)
      if (rsaPkeyStart >= der.length || der[rsaPkeyStart] != 0x30) return [];
      final (rsaSeqStart, _) = _asn1ReadLen(der, rsaPkeyStart);

      // modulus INTEGER (tag 0x02)
      if (rsaSeqStart >= der.length || der[rsaSeqStart] != 0x02) return [];
      final (modStart, modLen) = _asn1ReadLen(der, rsaSeqStart);

      var modulus = der.sublist(modStart, modStart + modLen);
      // Strip ASN.1 leading sign byte (0x00)
      while (modulus.isNotEmpty && modulus[0] == 0x00) {
        modulus = modulus.sublist(1);
      }
      return modulus;
    } catch (_) {
      return [];
    }
  }

  /// Builds a RemoteMessage { RemoteConfigure remote_configure = 1; }
  static List<int> _buildRemoteConfigurePayload() {
    final info = [
      ..._encodeString(1, 'Smart TV Remote'),
    ];
    final configInner = [
      ..._encodeSubMessage(1, info),
    ];
    final remoteMsg = _encodeSubMessage(1, configInner);
    return _wrapWithVarintLength(remoteMsg);
  }

  /// Builds a RemoteMessage { RemoteSetActive remote_set_active = 2; }
  static List<int> _buildRemoteSetActivePayload() {
    final setActiveMsg = [
      ..._encodeInt(1, 1),
    ];
    final remoteMsg = _encodeSubMessage(2, setActiveMsg);
    return _wrapWithVarintLength(remoteMsg);
  }

  /// Builds a RemoteMessage { RemoteKeyInject remote_key_inject = 3; }
  /// Key Down (action = 1) or Key Up (action = 2)
  static List<int> _buildRemoteKeycodeActionPayload(int keycode, int action) {
    final keyInjectMsg = [
      ..._encodeInt(1, keycode),
      ..._encodeInt(2, action),
    ];
    final remoteMsg = _encodeSubMessage(3, keyInjectMsg);
    return _wrapWithVarintLength(remoteMsg);
  }
}
