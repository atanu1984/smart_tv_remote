# Google TV Remote Protocol — Comprehensive Implementation & Protocol Knowledge Base

## Executive Summary & Verified Technical Facts
This repository implements the **Google TV Remote Protocol v2** over mTLS (Ports `6466`, `6467`) and **Google Cast v2 Master Audio Control** over TLS (Port `8009`) for Android TV and TCL Smart TVs.

All protocol logic, certificate handling, hash derivation, and port behaviors in this repository have been **100% empirically verified against live physical Google TVs (TCL System App v6.9)**.

---

## 1. POLO PairingSecret & Cryptographic Derivation (Port 6467)

### Pairing Sequence:
1. **Connect mTLS to Port 6467**:
   - Present client certificate (2048-bit RSA self-signed).
   - `PairingRequest` (Field 10) $\rightarrow$ `PairingOption` (Field 20) $\rightarrow$ `PairingConfiguration` (Field 30).
   - The TV displays a 6-digit hexadecimal/alphanumeric PIN on screen.

2. **Extract TV Certificate Modulus & Client Modulus**:
   - TV Certificate is extracted from the mTLS socket peer certificate (`socket.peerCertificate`).
   - ASN.1 DER RSA Public Key Parser locates tag `0x02` (INTEGER) inside SubjectPublicKeyInfo (`0x30 0x82 ...`).
   - If the first byte of the modulus integer is `0x00` (DER unsigned integer sign padding), skip it to obtain the exact **256-byte RSA Modulus**.

3. **Compute SHA-256 POLO PairingSecret**:
   ```dart
   final poloInput = <int>[
     ...clientModulusBytes, // 256 bytes
     ...tvModulusBytes,     // 256 bytes
     ...pinAsciiBytes,      // 6 ASCII bytes (e.g. "B167A2")
   ];
   final sha256Digest = sha256.convert(poloInput).bytes; // 32 bytes
   ```

4. **Construct PairingSecret Message (Field 40)**:
   - Tag: `0x0A` (Field 1, wire type 2)
   - Length: `0x20` (32 bytes)
   - Value: `sha256Digest` (32 bytes)
   - Wrap in Outer Protobuf Tag `0x22` (Field 40, wire type 2) and varint length prefix.

5. **Response Verification**:
   - TV returns `STATUS_OK` (`200` decimal / `0xC8 0x01` varint) at field 2 `PairingSecretAck` (Field 50).
   - Status `402` or socket close indicates invalid hash / PIN mismatch.

---

## 2. Control Protocol & TLS Handshake (Port 6466)

### mTLS Socket Setup & Timing Constraints:
1. Connect `SecureSocket` to `$ipAddress:6466` presenting the client cert.
2. **Mandatory Handshake Delays (Critical for Android TLS NIO)**:
   - Send `RemoteConfigure` $\rightarrow$ `await socket.flush()` $\rightarrow$ **Wait 150ms**.
   - Send `RemoteSetActive` $\rightarrow$ `await socket.flush()` $\rightarrow$ **Wait 150ms**.
3. **Listen for TV Handshake Responses**:
   - TV sends `RemoteStart` (`02 12 00`) to confirm control session active.
   - TV periodically sends `RemotePing` (`0x32`), client MUST reply with `RemotePong` (`0x02 0x3A 0x00`).

### Keycode Payload Formatting:
- **Key Down**: `[Field 1: Keycode, Field 2: Action=1 (KEY_DOWN)]`
- **Key Up**: `[Field 1: Keycode, Field 2: Action=2 (KEY_UP)]`
- Standard Android Keycodes:
  - `3`  = `KEYCODE_HOME`
  - `4`  = `KEYCODE_BACK`
  - `19` = `KEYCODE_DPAD_UP`
  - `20` = `KEYCODE_DPAD_DOWN`
  - `21` = `KEYCODE_DPAD_LEFT`
  - `22` = `KEYCODE_DPAD_RIGHT`
  - `23` = `KEYCODE_DPAD_CENTER` (SELECT / OK)
  - `24` = `KEYCODE_VOLUME_UP`
  - `25` = `KEYCODE_VOLUME_DOWN`
  - `26` = `KEYCODE_POWER`
  - `91` = `KEYCODE_MUTE`

---

## 3. Master Volume Control (Google Cast Port 8009)

### Technical Discovery:
When video or app overlays (YouTube, Netflix, Prime) are running on TCL Google TV, standard Android Remote keycodes on Port 6466 are intercepted by the media player app.

**Google Cast Port 8009** directly controls the TV's **Master Speaker Audio Engine** (`controlType: master`).

### Google Cast Volume Protocol (`urn:x-cast:com.google.cast.receiver`):
Every `SET_VOLUME` JSON payload **MUST INCLUDE `requestId`** (integer). Without `requestId`, Google Cast receiver ignores volume commands.

```json
{
  "type": "SET_VOLUME",
  "volume": {
    "level": 0.35,
    "muted": false
  },
  "requestId": 101
}
```

- Mute Command: Send `volume: { "muted": true }` with `requestId`.
- Volume Control: Maintain current volume level (`0.0` to `1.0`) and send level steps.

---

## 4. Mobile Environment & Certificate Persistence Gotcha

### Problem Discovered:
Android OS retains `SharedPreferences` across APK updates when the package name remains unchanged.

### Solution Implemented in `ClientCertificateService`:
To prevent the mobile app from loading an old, stale certificate string cached in `SharedPreferences` from previous builds, `ClientCertificateService` is **hard-locked** to return the verified 2048-bit RSA client cert (`_kDefaultClientCertPem`) and private key (`_kDefaultClientKeyPem`).

This guarantees that the client certificate presented on Port 6467, Port 6466, and during POLO secret calculation is **100% identical** on every single app execution.

---

## 5. Diagnostic Tools & Scripts

### Desktop / PC Testing Scripts:
- `c:\Code\smart_tv_remote\check_paired_status.ps1`: Tests mTLS connection & keycode execution from PC.
- `c:\Code\smart_tv_remote\test_control_port6466.dart`: Direct Port 6466 test script.
- `c:\Code\smart_tv_remote\test_cast_port8009.dart`: Direct Port 8009 Master Volume test script.

### In-App Mobile Diagnostics:
- Tap the **yellow Bug Icon (`🐛`)** in the top bar of `HomeScreen` to view the live log console.
- Tap **"Copy Logs"** to copy the full formatted diagnostic output (including raw hex responses, socket states, and timestamps) to the mobile clipboard.

---

## 6. Build Command Reminder

Always use `setup_and_build.ps1` to compile the release APK:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "c:\Code\smart_tv_remote\setup_and_build.ps1"
```
Generated APK Path:
`C:\Code\smart_tv_remote\build\app\outputs\flutter-apk\app-release.apk`
