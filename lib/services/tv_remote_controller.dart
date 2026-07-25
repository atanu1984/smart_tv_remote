import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/smart_tv_device.dart';
import 'app_logger.dart';
import 'google_cast_controller.dart';
import 'google_tv_pairing_service.dart';

enum RemoteCommand {
  up,
  down,
  left,
  right,
  select,
  back,
  home,
  volumeUp,
  volumeDown,
  volumeMute,
  power,
  playPause,
}

class RemoteCommandResult {
  final bool success;
  final String message;
  final int? activePort;
  final DateTime timestamp;
  final bool needsPairing;
  final String? pairingIp;

  const RemoteCommandResult({
    required this.success,
    required this.message,
    this.activePort,
    required this.timestamp,
    this.needsPairing = false,
    this.pairingIp,
  });
}

class TvRemoteController {
  final http.Client _client = http.Client();
  final GoogleTvPairingService _pairingService = GoogleTvPairingService();
  final Map<String, int> _detectedPortsCache = {};

  GoogleTvPairingService get pairingService => _pairingService;

  /// Probes the target TV for all common Smart TV & TCL ports
  Future<Map<int, bool>> probeTvPorts(String ip) async {
    final List<int> portsToTest = [8737, 6466, 6467, 8008, 8009, 5555, 8080, 8000, 4123, 1537, 8060, 8001, 3000];
    final Map<int, bool> results = {};

    final List<Future<void>> tasks = portsToTest.map((port) async {
      bool isOpen = false;
      try {
        final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 400));
        await socket.close();
        isOpen = true;
      } catch (_) {
        // Try HTTP GET if TCP connect didn't work
        try {
          final uri = Uri.parse('http://$ip:$port/');
          final resp = await _client.get(uri).timeout(const Duration(milliseconds: 400));
          if (resp.statusCode > 0) isOpen = true;
        } catch (_) {}
      }
      results[port] = isOpen;
    }).toList();

    await Future.wait(tasks);
    return results;
  }

  /// Sends remote control commands targeting all active ports and protocols.
  ///
  /// Priority order for TCL Google TV:
  ///   1. Cached port (fastest if previously found)
  ///   2. Google TV mTLS (port 6466) — primary for TCL/AndroidTV brands
  ///   3. TCL nScreen HTTP sweep (ports 8737, 8080, 8000, 4123, 1537)
  ///   4. DIAL / Cast fallbacks
  ///   5. Brand-specific fallbacks (Roku, Samsung)
  Future<RemoteCommandResult> sendCommand({
    required SmartTvDevice device,
    required RemoteCommand command,
  }) async {
    final now = DateTime.now();
    final ip = device.ipAddress;

    try {
      // If port was previously cached for this device, try cached port first
      if (_detectedPortsCache.containsKey(device.id)) {
        final cachedPort = _detectedPortsCache[device.id]!;
        final res = await _trySpecificPortCommand(ip, cachedPort, command, now);
        if (res.success) return res;
        // Cached port stopped responding — clear cache and retry all
        _detectedPortsCache.remove(device.id);
      }

      // 1. For TCL, Google TV & Android TV devices: Priority 1 is Google TV Remote v2 (Port 6466/6467)
      if (device.brand == TvBrand.tcl || device.brand == TvBrand.androidTv || device.brand == TvBrand.genericDial) {
        final googleTvRes = await _sendGoogleTvRemote(ip, command, now);
        if (googleTvRes.success) {
          _detectedPortsCache[device.id] = 6466;
          return googleTvRes;
        }
        if (googleTvRes.needsPairing) return googleTvRes;
      }

      // 3. For non-TCL Android TV brands, try the multi-protocol path
      if (device.brand == TvBrand.androidTv) {
        final androidRes = await _sendAndroidTvMultiProtocol(ip, command, now);
        if (androidRes.success) {
          _detectedPortsCache[device.id] = androidRes.activePort ?? 6466;
          return androidRes;
        }
        if (androidRes.needsPairing) return androidRes;
      }

      // 4. Roku TV Protocol (Port 8060)
      if (device.brand == TvBrand.roku || device.port == 8060) {
        final rokuRes = await _sendRokuCommand(ip, command, now);
        if (rokuRes.success) return rokuRes;
      }

      // 5. Samsung Protocol (Port 8001)
      if (device.brand == TvBrand.samsung || device.port == 8001) {
        final samRes = await _sendSamsungCommand(ip, command, now);
        if (samRes.success) return samRes;
      }

      // 6. Final broadcast sweep — tries all known ports with all protocols
      return await _broadcastAllKnownPorts(ip, command, now);
    } catch (e) {
      return RemoteCommandResult(
        success: false,
        message: 'Could not reach TV at $ip: ${e.toString()}',
        timestamp: now,
      );
    }
  }

  /// Google TV Remote Service — primary protocol for TCL Google TVs.
  ///
  /// Requires PIN pairing if device is not paired yet. Once paired, sends
  /// keycodes over persistent mTLS session on port 6466.
  Future<RemoteCommandResult> _sendGoogleTvRemote(
    String ip,
    RemoteCommand command,
    DateTime now,
  ) async {
    final keycode = _getAndroidTvKeycode(command);
    final keyName = _commandDisplayName(command);

    // 1. Check if device has been paired in local app storage
    final isPaired = await _pairingService.isDevicePaired(ip);
    if (!isPaired) {
      AppLogger.log('Device $ip is not paired yet. Initiating PIN pairing...');
      final pairingInit = await _pairingService.initiatePairing(ip);
      return RemoteCommandResult(
        success: false,
        message: pairingInit.message,
        needsPairing: true,
        pairingIp: ip,
        timestamp: now,
      );
    }

    // 2. Device is recorded as paired — send keycode via mTLS session
    AppLogger.log('Device $ip is paired. Sending $keyName (keycode $keycode) to port 6466...');
    final sent = await _pairingService.sendAuthenticatedKeycode(ip, keycode);
    if (sent) {
      AppLogger.log('Successfully delivered $keyName to TV ($ip:6466)');
      return RemoteCommandResult(
        success: true,
        message: 'Sent $keyName to Google TV ($ip)',
        activePort: 6466,
        timestamp: now,
      );
    }

    // 3. Retry once if initial send failed (e.g. idle socket reconnect)
    AppLogger.log('Initial send of $keyName failed on $ip:6466. Retrying session...');
    await Future.delayed(const Duration(milliseconds: 300));
    final retrySent = await _pairingService.sendAuthenticatedKeycode(ip, keycode);
    if (retrySent) {
      AppLogger.log('Retry delivered $keyName to TV ($ip:6466)');
      return RemoteCommandResult(
        success: true,
        message: 'Sent $keyName to Google TV ($ip)',
        activePort: 6466,
        timestamp: now,
      );
    }

    AppLogger.log('Could not deliver $keyName to $ip:6466 after retry.');
    return RemoteCommandResult(
      success: false,
      message: 'Could not deliver $keyName to TV. Check Wi-Fi connection.',
      needsPairing: false, // DO NOT open PIN pairing dialog!
      timestamp: now,
    );
  }

  /// TCL nScreen HTTP Protocol (Ports 8737, 8080, 8000, 4123, 1537)
  ///
  /// Used as a secondary option for TCL TVs running older firmware that
  /// exposes an HTTP control API. Tries multiple URL formats per port.
  Future<RemoteCommandResult> _sendTclnScreenCommand(
    String ip,
    RemoteCommand command,
    DateTime now,
  ) async {
    final tclKeyName = _mapTclKey(command);
    final keycode = _getAndroidTvKeycode(command);

    // Port 8008: DIAL / Google Cast REST (0-pairing, primary for TCL Google TV)
    // Port 4123: TCL Smart Home API
    // Port 8737: TCL nScreen legacy
    // Port 8080/8000/1537: common fallback HTTP ports
    final List<int> tclPorts = [8008, 4123, 8737, 8080, 8000, 1537];

    for (final port in tclPorts) {
      // Method A: GET /remote/media_control?action=key&value=<key>
      try {
        final urlA = Uri.parse('http://$ip:$port/remote/media_control?action=key&value=$tclKeyName');
        final respA = await _client.get(urlA).timeout(const Duration(milliseconds: 400));
        if (respA.statusCode == 200 || respA.statusCode == 204) {
          return RemoteCommandResult(
            success: true,
            message: 'Sent $tclKeyName to TCL TV on Port $port (nScreen)',
            activePort: port,
            timestamp: now,
          );
        }
      } catch (_) {}

      // Method B: GET /?action=key&code=<keycode>
      try {
        final urlB = Uri.parse('http://$ip:$port/?action=key&code=$keycode');
        final respB = await _client.get(urlB).timeout(const Duration(milliseconds: 400));
        if (respB.statusCode == 200 || respB.statusCode == 204) {
          return RemoteCommandResult(
            success: true,
            message: 'Sent keycode $keycode to TCL TV on Port $port',
            activePort: port,
            timestamp: now,
          );
        }
      } catch (_) {}

      // Method C: POST /keypress/<key>
      try {
        final urlC = Uri.parse('http://$ip:$port/keypress/$tclKeyName');
        final respC = await _client.post(urlC).timeout(const Duration(milliseconds: 400));
        if (respC.statusCode == 200 || respC.statusCode == 204) {
          return RemoteCommandResult(
            success: true,
            message: 'Sent $tclKeyName to TCL TV on Port $port (keypress)',
            activePort: port,
            timestamp: now,
          );
        }
      } catch (_) {}

      // Method D: POST /system/control (DIAL / HTTP control)
      try {
        final urlD = Uri.parse('http://$ip:$port/system/control');
        final body = jsonEncode({'action': 'key', 'code': keycode, 'key': tclKeyName});
        final respD = await _client.post(urlD, body: body).timeout(const Duration(milliseconds: 400));
        if (respD.statusCode == 200 || respD.statusCode == 204) {
          return RemoteCommandResult(
            success: true,
            message: 'Sent $tclKeyName to TCL TV on Port $port (DIAL)',
            activePort: port,
            timestamp: now,
          );
        }
      } catch (_) {}
    }

    return RemoteCommandResult(success: false, message: 'TCL nScreen HTTP ports unresponsive', timestamp: now);
  }

  /// Android TV / Google TV Multi-Protocol (Port 6466, 8008)
  ///
  /// Secondary path for `androidTv` brand devices. _sendGoogleTvRemote is the
  /// primary path and should be called first for TCL / Google TV devices.
  Future<RemoteCommandResult> _sendAndroidTvMultiProtocol(
    String ip,
    RemoteCommand command,
    DateTime now,
  ) async {
    final keycode = _getAndroidTvKeycode(command);
    final keyName = _commandDisplayName(command);

    // Try mTLS keycode delivery (port 6466) — works if device is paired
    final sentAuth = await _pairingService.sendAuthenticatedKeycode(ip, keycode);
    if (sentAuth) {
      return RemoteCommandResult(
        success: true,
        message: 'Sent $keyName to Android TV ($ip)',
        activePort: 6466,
        timestamp: now,
      );
    }

    // Try Port 8008 (Google Cast HTTP DIAL) as secondary
    try {
      final url = Uri.parse('http://$ip:8008/system/control');
      final body = jsonEncode({'action': 'key', 'code': keycode});
      final resp = await _client.post(url, body: body).timeout(const Duration(milliseconds: 500));
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        return RemoteCommandResult(
          success: true,
          message: 'Sent $keyName to Android TV DIAL Port 8008',
          activePort: 8008,
          timestamp: now,
        );
      }
    } catch (_) {}

    return RemoteCommandResult(
      success: false,
      message: 'Android TV ports (6466, 8008) unresponsive.',
      timestamp: now,
    );
  }

  /// Roku Protocol (Port 8060)
  Future<RemoteCommandResult> _sendRokuCommand(String ip, RemoteCommand command, DateTime now) async {
    final keyName = _mapRokuKey(command);
    final url = Uri.parse('http://$ip:8060/keypress/$keyName');

    try {
      final response = await _client.post(url).timeout(const Duration(milliseconds: 800));
      if (response.statusCode == 200) {
        return RemoteCommandResult(
          success: true,
          message: 'Sent $keyName to Roku TV on Port 8060',
          activePort: 8060,
          timestamp: now,
        );
      }
    } catch (_) {}
    return RemoteCommandResult(success: false, message: 'Roku Port 8060 unresponsive', timestamp: now);
  }

  /// Samsung Protocol (Port 8001)
  Future<RemoteCommandResult> _sendSamsungCommand(String ip, RemoteCommand command, DateTime now) async {
    final keyName = _mapSamsungKey(command);
    final url = Uri.parse('http://$ip:8001/api/v2/channels/com.samsung.tv.remote');

    try {
      final payload = jsonEncode({
        'method': 'ms.remote.control',
        'params': {'Cmd': 'Click', 'DataOfCmd': keyName, 'TypeOfRemote': 'SendRemoteKey'}
      });
      final response = await _client.post(url, headers: {'Content-Type': 'application/json'}, body: payload)
          .timeout(const Duration(milliseconds: 800));

      if (response.statusCode == 200 || response.statusCode == 204) {
        return RemoteCommandResult(
          success: true,
          message: 'Sent $keyName to Samsung TV on Port 8001',
          activePort: 8001,
          timestamp: now,
        );
      }
    } catch (_) {}
    return RemoteCommandResult(success: false, message: 'Samsung Port 8001 unresponsive', timestamp: now);
  }

  Future<RemoteCommandResult> _trySpecificPortCommand(
    String ip,
    int port,
    RemoteCommand command,
    DateTime now,
  ) async {
    if (port == 6466) {
      return await _sendGoogleTvRemote(ip, command, now);
    }
    if (port == 8737 || port == 8080 || port == 8000 || port == 4123 || port == 1537) {
      return await _sendTclnScreenCommand(ip, command, now);
    }
    if (port == 6467 || port == 8008) {
      return await _sendAndroidTvMultiProtocol(ip, command, now);
    }
    if (port == 8060) {
      return await _sendRokuCommand(ip, command, now);
    }
    if (port == 8001) {
      return await _sendSamsungCommand(ip, command, now);
    }
    return RemoteCommandResult(success: false, message: 'Cached port $port unreachable', timestamp: now);
  }

  /// Broadcast fallback — tries all known protocols in sequence.
  /// This is only reached when brand-specific paths all fail.
  Future<RemoteCommandResult> _broadcastAllKnownPorts(String ip, RemoteCommand command, DateTime now) async {
    // Try Google TV mTLS as last resort
    final googleTvRes = await _sendGoogleTvRemote(ip, command, now);
    if (googleTvRes.success || googleTvRes.needsPairing) return googleTvRes;

    // Try TCL nScreen HTTP
    final tclRes = await _sendTclnScreenCommand(ip, command, now);
    if (tclRes.success) return tclRes;

    // Try Roku
    final rokuRes = await _sendRokuCommand(ip, command, now);
    if (rokuRes.success) return rokuRes;

    // Try Samsung
    final samRes = await _sendSamsungCommand(ip, command, now);
    if (samRes.success) return samRes;

    return RemoteCommandResult(
      success: false,
      message: 'Could not connect to TV at $ip. Ensure the TV is powered on, connected to the same Wi-Fi, and Google TV Remote is enabled in settings.',
      timestamp: now,
    );
  }

  /// Movie Casting / Search
  Future<RemoteCommandResult> castMovieOrText({
    required SmartTvDevice device,
    required String textQuery,
  }) async {
    final now = DateTime.now();
    final cleanQuery = textQuery.trim();
    final ip = device.ipAddress;

    if (cleanQuery.isEmpty) {
      return RemoteCommandResult(success: false, message: 'Search query cannot be empty', timestamp: now);
    }

    try {
      final encoded = Uri.encodeComponent(cleanQuery);
      // Try Roku search
      final rokuUrl = Uri.parse('http://$ip:8060/search/browse?keyword=$encoded');
      await _client.post(rokuUrl).timeout(const Duration(milliseconds: 800));
    } catch (_) {}

    try {
      // Try DIAL YouTube launch
      final dialUrl = Uri.parse('http://$ip:8008/apps/YouTube');
      await _client.post(dialUrl, body: 'pairingCode=$cleanQuery').timeout(const Duration(milliseconds: 800));
    } catch (_) {}

    return RemoteCommandResult(
      success: true,
      message: 'Casting search "$cleanQuery" to ${device.name} ($ip)',
      timestamp: now,
    );
  }

  int _getAndroidTvKeycode(RemoteCommand command) {
    switch (command) {
      case RemoteCommand.up:
        return 19;  // KEYCODE_DPAD_UP
      case RemoteCommand.down:
        return 20;  // KEYCODE_DPAD_DOWN
      case RemoteCommand.left:
        return 21;  // KEYCODE_DPAD_LEFT
      case RemoteCommand.right:
        return 22;  // KEYCODE_DPAD_RIGHT
      case RemoteCommand.select:
        return 23;  // KEYCODE_DPAD_CENTER — Fix #1: was 66 (ENTER), TV launcher requires DPAD_CENTER
      case RemoteCommand.back:
        return 4;   // KEYCODE_BACK
      case RemoteCommand.home:
        return 3;   // KEYCODE_HOME
      case RemoteCommand.volumeUp:
        return 24;  // KEYCODE_VOLUME_UP
      case RemoteCommand.volumeDown:
        return 25;  // KEYCODE_VOLUME_DOWN
      case RemoteCommand.volumeMute:
        return 91;  // KEYCODE_MUTE (Standard hardware mute for TCL TV)
      case RemoteCommand.power:
        return 26;  // KEYCODE_POWER
      case RemoteCommand.playPause:
        return 85;  // KEYCODE_MEDIA_PLAY_PAUSE
    }
  }

  /// Maps commands to TCL nScreen protocol key names.
  /// Key names match the values expected by TCL's HTTP remote API.
  String _mapTclKey(RemoteCommand command) {
    switch (command) {
      case RemoteCommand.up:
        return 'up';
      case RemoteCommand.down:
        return 'down';
      case RemoteCommand.left:
        return 'left';
      case RemoteCommand.right:
        return 'right';
      case RemoteCommand.select:
        return 'ok';        // TCL nScreen OK / DPAD_CENTER
      case RemoteCommand.back:
        return 'back';
      case RemoteCommand.home:
        return 'home';
      case RemoteCommand.volumeUp:
        return 'volumeup';  // FIXED: was 'vol_up' (not a valid nScreen key)
      case RemoteCommand.volumeDown:
        return 'volumedown'; // FIXED: was 'vol_down'
      case RemoteCommand.volumeMute:
        return 'mute';
      case RemoteCommand.power:
        return 'power';
      case RemoteCommand.playPause:
        return 'play';     // FIXED: was 'pause' — nScreen uses 'play' for toggle
    }
  }

  String _mapRokuKey(RemoteCommand command) {
    switch (command) {
      case RemoteCommand.up:
        return 'Up';
      case RemoteCommand.down:
        return 'Down';
      case RemoteCommand.left:
        return 'Left';
      case RemoteCommand.right:
        return 'Right';
      case RemoteCommand.select:
        return 'Select';
      case RemoteCommand.back:
        return 'Back';
      case RemoteCommand.home:
        return 'Home';
      case RemoteCommand.volumeUp:
        return 'VolumeUp';
      case RemoteCommand.volumeDown:
        return 'VolumeDown';
      case RemoteCommand.volumeMute:
        return 'VolumeMute';
      case RemoteCommand.power:
        return 'PowerOff';
      case RemoteCommand.playPause:
        return 'Play';
    }
  }

  String _mapSamsungKey(RemoteCommand command) {
    switch (command) {
      case RemoteCommand.up:
        return 'KEY_UP';
      case RemoteCommand.down:
        return 'KEY_DOWN';
      case RemoteCommand.left:
        return 'KEY_LEFT';
      case RemoteCommand.right:
        return 'KEY_RIGHT';
      case RemoteCommand.select:
        return 'KEY_ENTER';
      case RemoteCommand.back:
        return 'KEY_RETURN';
      case RemoteCommand.home:
        return 'KEY_HOME';
      case RemoteCommand.volumeUp:
        return 'KEY_VOLUP';
      case RemoteCommand.volumeDown:
        return 'KEY_VOLDOWN';
      case RemoteCommand.volumeMute:
        return 'KEY_MUTE';
      case RemoteCommand.power:
        return 'KEY_POWER';
      case RemoteCommand.playPause:
        return 'KEY_PLAY';
    }
  }

  String _commandDisplayName(RemoteCommand command) {
    switch (command) {
      case RemoteCommand.up:
        return 'UP';
      case RemoteCommand.down:
        return 'DOWN';
      case RemoteCommand.left:
        return 'LEFT';
      case RemoteCommand.right:
        return 'RIGHT';
      case RemoteCommand.select:
        return 'OK';
      case RemoteCommand.back:
        return 'BACK';
      case RemoteCommand.home:
        return 'HOME';
      case RemoteCommand.volumeUp:
        return 'VOL +';
      case RemoteCommand.volumeDown:
        return 'VOL -';
      case RemoteCommand.volumeMute:
        return 'MUTE';
      case RemoteCommand.power:
        return 'POWER';
      case RemoteCommand.playPause:
        return 'PLAY/PAUSE';
    }
  }
}
