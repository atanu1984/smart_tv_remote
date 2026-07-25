# Smart TV Remote App

A modern dark-themed Smart TV Wi-Fi Remote Flutter app designed for **TCL Google TV**, Android TV, Roku, Samsung, and LG.

## Quick Start & Build Instructions

To build the release APK cleanly without version or path issues, always run the automated PowerShell script:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup_and_build.ps1"
```

### Output APK Path
`build\app\outputs\flutter-apk\app-release.apk`

---

## Technical Specifications & Documentation
- Full Architecture, Data Models, Protocols, & Setup: See [spec.md](spec.md)
- Agent & Environment Rules: See [.agents/AGENTS.md](.agents/AGENTS.md)

---

## Environment Prerequisites
- **Flutter SDK**: `C:\src\flutter`
- **JDK 17**: `C:\Android\jdk-17.0.10+7` (Must set `$env:JAVA_HOME`)
- **Android SDK**: `C:\Android\sdk`

### Configured Versions
- **AGP**: `8.11.1`
- **Kotlin**: `2.1.0`
- **Gradle**: `8.14.1`
- **NDK**: `28.2.13676358` (`ndkVersion` in `android/app/build.gradle`)
