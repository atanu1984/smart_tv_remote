# Smart TV Remote — App Specification

> **Version**: 1.0.0  
> **Platform**: Android (Flutter)  
> **Target TVs**: TCL Google TV (primary), Android TV, Roku, Samsung, LG  
> **Author**: Auto-generated spec from source code analysis

---

## 1. Overview

**Smart TV Remote** is a Flutter-based Android application that replaces a physical TV remote using your phone over Wi-Fi. It supports multiple TV brands and protocols, with TCL Google TV as the primary target device.

The app connects to a TV on the **same local Wi-Fi network** and sends remote control keypresses via industry standard protocols including Google TV Remote mTLS (port 6466), TCL nScreen HTTP API, Roku ECP, and Samsung Smart API.

---

## 2. Architecture

```
lib/
+-- main.dart                            # App entry point
+-- models/
¦   +-- smart_tv_device.dart             # SmartTvDevice model + TvBrand enum
¦   +-- network_state.dart               # Network status model
+-- screens/
¦   +-- home_screen.dart                 # Main remote control UI
¦   +-- scanner_screen.dart              # Device discovery + manual IP entry
+-- services/
¦   +-- tv_remote_controller.dart        # Command routing (primary service)
¦   +-- google_tv_pairing_service.dart   # mTLS session + PIN pairing
¦   +-- network_discovery_service.dart   # Orchestrates SSDP + HTTP scan
¦   +-- ssdp_scanner.dart                # SSDP/UPnP multicast discovery
¦   +-- http_subnet_scanner.dart         # TCP/HTTP port sweep discovery
¦   +-- wifi_service.dart                # Wi-Fi status + subnet detection
¦   +-- speech_service.dart              # Voice search (future feature)
+-- widgets/
¦   +-- dpad_widget.dart                 # Directional pad (Up/Down/Left/Right/OK)
¦   +-- action_buttons.dart              # Power, Back, Home, Play/Pause
¦   +-- volume_control.dart              # Vol+, Vol-, Mute toggle
¦   +-- device_selector.dart             # Connected TV header + pairing tips
¦   +-- search_cast_bar.dart             # Movie cast / YouTube search bar
¦   +-- pin_pairing_dialog.dart          # PIN entry dialog for Google TV pairing
¦   +-- voice_remote_widget.dart         # Voice search UI
+-- theme/
    +-- app_theme.dart                   # Design tokens, gradients, glass style
```

---

## 3. Supported TV Brands & Protocols

| Brand | Enum | Primary Port | Protocol |
|-------|------|--------------|----------|
| TCL Google TV | `TvBrand.tcl` | 6466 | Google TV Remote mTLS (Protobuf) |
| Android / Google TV | `TvBrand.androidTv` | 6466 | Google TV Remote mTLS (Protobuf) |
| Roku | `TvBrand.roku` | 8060 | Roku ECP (HTTP POST) |
| Samsung | `TvBrand.samsung` | 8001 | Samsung Smart API (HTTP JSON) |
| LG | `TvBrand.lg` | 3000 | webOS REST API |
| Generic DIAL/UPnP | `TvBrand.genericDial` | 6466 | Google TV mTLS fallback |

---

## 4. Remote Commands

| Command | Android Keycode | TCL nScreen Key | Roku Key | Samsung Key |
|---------|----------------|-----------------|----------|-------------|
| Up | 19 (DPAD_UP) | `up` | `Up` | `KEY_UP` |
| Down | 20 (DPAD_DOWN) | `down` | `Down` | `KEY_DOWN` |
| Left | 21 (DPAD_LEFT) | `left` | `Left` | `KEY_LEFT` |
| Right | 22 (DPAD_RIGHT) | `right` | `Right` | `KEY_RIGHT` |
| Select / OK | 23 (DPAD_CENTER) | `ok` | `Select` | `KEY_ENTER` |
| Back | 4 (BACK) | `back` | `Back` | `KEY_RETURN` |
| Home | 3 (HOME) | `home` | `Home` | `KEY_HOME` |
| Volume Up | 24 (VOLUME_UP) | `volumeup` | `VolumeUp` | `KEY_VOLUP` |
| Volume Down | 25 (VOLUME_DOWN) | `volumedown` | `VolumeDown` | `KEY_VOLDOWN` |
| Mute | 164 (VOLUME_MUTE) | `mute` | `VolumeMute` | `KEY_MUTE` |
| Power | 26 (POWER) | `power` | `PowerOff` | `KEY_POWER` |
| Play/Pause | 85 (MEDIA_PLAY_PAUSE) | `play` | `Play` | `KEY_PLAY` |

---

## 5. Command Routing Flow

When the user presses any remote button, `TvRemoteController.sendCommand()` is called and follows this priority cascade:

```
Button Press
    |
    v
[1] Cached port? --> TrySpecificPortCommand() --> SUCCESS
    | fail
    v
[2] Brand == tcl | androidTv | genericDial?
    |
    +-- sendGoogleTvRemote()
    |     +-- sendAuthenticatedKeycode(port 6466 mTLS) --> SUCCESS
    |     |   fail
    |     +-- Port 6467 reachable? --> initiatePairing() --> PIN DIALOG
    |         not reachable --> continue
    v
[3] sendTclnScreenCommand() (ports 8737, 4123, 8080, 8000, 1537)
    |   Method A: GET /remote/media_control?action=key&value=<key>
    |   Method B: GET /?action=key&code=<keycode>
    |   Method C: POST /keypress/<key>
    |   --> SUCCESS
    | fail
    v
[4] Brand == androidTv? --> sendAndroidTvMultiProtocol()
    |   port 6466 mTLS --> SUCCESS
    |   port 8008 DIAL --> SUCCESS
    | fail
    v
[5] Brand == roku --> sendRokuCommand() port 8060 --> SUCCESS
    |
    v
[6] Brand == samsung --> sendSamsungCommand() port 8001 --> SUCCESS
    |
    v
[7] broadcastAllKnownPorts() -- last resort sweep
```

---

## 6. Google TV Pairing Protocol

TCL Google TVs require mutual TLS (mTLS) authentication before accepting keycode commands.

### Phase 1 - Initiate Pairing
1. App connects to TV on **port 6467** via TLS with embedded client certificate
2. Sends a Protobuf PairingRequest: { service_name: "androidtvremote2", client_name: "Smart TV Remote" }
3. TV displays a **4-6 character PIN** on-screen
4. App returns needsPairing: true --> PinPairingDialog is shown

### Phase 2 - Verify PIN
1. User enters PIN in dialog
2. App sends Protobuf PairingSecret with the PIN bytes
3. TV responds (or closes connection gracefully) = success
4. App saves IP to SharedPreferences under key: `google_tv_paired_devices_v2`

### Phase 3 - Send Keys (post-pairing)
1. App connects to TV on **port 6466** with the same client certificate
2. TV sends RemoteStart { started: true }
3. App sends RemoteMessage { RemoteKeyInject { key_code, direction=SHORT } }
4. TV sends periodic RemotePing --> App responds with RemotePong (keeps connection alive)
5. Session is cached in memory and reused for subsequent key presses

### Client Certificate
The app uses a shared embedded self-signed certificate (valid 10 years). The TV pairs the certificate fingerprint during PIN verification. This is the standard approach used by all Google TV remote apps.

---

## 7. Device Discovery

### 7.1 SSDP / UPnP Multicast
- Sends M-SEARCH to `239.255.255.250:1900`
- Parses `LOCATION` headers to fetch UPnP device description XML
- Extracts `<friendlyName>`, `<manufacturer>` for brand detection
- Brand detected by keyword match: tcl, roku, samsung, lg, android, google

### 7.2 HTTP Subnet Sweep
Parallel TCP/HTTP probes across /24 subnet (e.g. 192.168.1.1-254):

| TV Brand | Port | Probe Method |
|----------|------|--------------|
| Android / TCL | 8008 | GET /setup/configured_networks |
| TCL Google TV | 6466 | TCP Socket connect |
| Roku | 8060 | GET /query/device-info (XML parse) |
| Samsung | 8001 | GET /api/v2/ |
| LG | 3000 | GET / (webos body/header check) |

### 7.3 Manual IP Entry
User can type a TV IP address directly in the Scanner screen. Manual devices are assigned `TvBrand.tcl`.

### 7.4 Demo Devices (Fallback)
When no real TVs are found, the app shows 4 demo devices:
- Living Room Roku Ultra (192.168.x.105)
- Master Bedroom Samsung QLED (192.168.x.112)
- Home Theater LG OLED (192.168.x.120)
- **TCL Google TV 55"** (192.168.x.130)

---

## 8. Data Models

### SmartTvDevice
```dart
class SmartTvDevice {
  final String id;             // Unique device identifier
  final String originalName;   // Name from discovery
  final String? customName;    // User-renamed display name
  final TvBrand brand;         // Enum: tcl, androidTv, roku, samsung, lg, genericDial
  final String ipAddress;      // e.g. "192.168.1.105"
  final int port;              // Primary port for this device
  final String? modelName;     // e.g. "TCL 55C745"
  final String? manufacturer;  // e.g. "TCL Electronics"
  final String? serialNumber;
  final String discoveryMethod;
  final DateTime lastSeen;
  final bool isOnline;
}
```

### RemoteCommandResult
```dart
class RemoteCommandResult {
  final bool success;
  final String message;      // User-facing status message
  final int? activePort;     // Port that responded
  final DateTime timestamp;
  final bool needsPairing;   // Show PIN dialog if true
  final String? pairingIp;   // IP for pairing dialog
}
```

---

## 9. UI Screens & Widgets

### HomeScreen
- Wi-Fi status bar (SSID, signal strength, subnet)
- DeviceSelectorHeader (connected TV, rename button, scan shortcut)
- SearchCastBar (movie/app search with quick suggestion chips)
- ActionButtonsWidget (Power, Back, Home, Play/Pause)
- DPadWidget (circular directional pad with central OK button)
- VolumeControlWidget (Vol-, Mute toggle, Vol+ with animated mute state)

### ScannerScreen
- Full device list from SSDP + HTTP sweep
- Progress indicator during scan
- Manual IP input field
- Device cards with brand icon, IP, discovery method
- Tap to connect and return to HomeScreen

### PinPairingDialog
- Auto-triggered when TV requires initial pairing
- PIN input with large letter-spaced text field
- Animated submit spinner
- Error message on wrong PIN

---

## 10. Android Permissions

Declared in AndroidManifest.xml:
- `INTERNET` -- for HTTP requests to TV
- `ACCESS_NETWORK_STATE` -- to check Wi-Fi connectivity
- `ACCESS_WIFI_STATE` -- to get SSID and subnet prefix
- `CHANGE_WIFI_MULTICAST_STATE` -- for SSDP multicast discovery

---

## 11. Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Core framework |
| `http` | ^1.2.1 | HTTP requests to TV APIs |
| `dio` | ^5.4.3 | Advanced HTTP (cast/search) |
| `shared_preferences` | ^2.2.2 | Persist paired device IPs |
| `google_fonts` | ^6.1.0 | Typography |
| `flutter_riverpod` | ^2.5.1 | State management |
| `connectivity_plus` | ^6.0.3 | Network connectivity detection |
| `network_info_plus` | ^5.0.3 | Wi-Fi SSID + IP address |
| `flutter_animate` | ^4.5.0 | Micro-animations |
| `font_awesome_flutter` | ^10.7.0 | Extended icon set |

---

## 12. Build & Installation

### Release APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Install via ADB
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## 13. Known Limitations

| Limitation | Details |
|------------|---------|
| One-time PIN pairing required | TCL Google TV requires one-time mTLS pairing per device |
| Same Wi-Fi network only | TV and phone must be on the same LAN subnet |
| TCL nScreen availability | HTTP control API (port 8737) not available on all TCL firmware versions |
| Shared client certificate | All installs share the same embedded cert |
| LG not fully implemented | TvBrand.lg is detected but no LG-specific keycode handler |
| ADB not supported | ADB requires full CNXN/OPEN/WRITE handshake; raw socket write is ignored |

---

## 14. Setup Steps for TCL Google TV

1. Connect both phone and TCL TV to the same Wi-Fi network
2. On the TCL TV: Settings > Device Preferences > Remote & Accessories > Pair remote or accessory
   (Or ensure Android TV Remote Service is enabled)
3. Open the app > tap the scan icon to discover your TV
4. Select your TCL TV from the list (or enter IP manually)
5. Tap any button -- a PIN code will appear on your TV screen
6. Enter the PIN in the app dialog > tap Pair Remote
7. All buttons now work! Pairing is saved for future sessions.
