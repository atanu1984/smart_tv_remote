# Smart TV Remote — Workspace Rules & Environment Notes

## Quick Build Command
Always use `setup_and_build.ps1` to build the app:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "c:\Code\smart_tv_remote\setup_and_build.ps1"
```

## Environment Prerequisites & Configuration
- **Flutter SDK Location**: `C:\src\flutter`
- **JDK 17 Location**: `C:\Android\jdk-17.0.10+7` or `C:\src\jdk-17`
  - *CRITICAL*: Do NOT rely on system default `java` (it is Java 8 and will fail AGP compilation). Always set `$env:JAVA_HOME = "C:\Android\jdk-17.0.10+7"`.
- **Android SDK Location**: `C:\Android\sdk`

## Version Requirements (Do Not Downgrade)
- **Android Gradle Plugin (AGP)**: `8.11.1` (`android/settings.gradle` & `android/build.gradle`)
- **Kotlin Gradle Plugin**: `2.1.0` (`android/settings.gradle` & `android/build.gradle`)
- **Gradle Wrapper**: `8.14.1` (`android/gradle/wrapper/gradle-wrapper.properties`)
- **Android NDK**: `28.2.13676358` pinned via `ndkVersion = "28.2.13676358"` in `android/app/build.gradle`.

## Troubleshooting & File Lock Recovery
If Gradle fails with `Execution failed for task ':app:configureCMakeRelease'` or folder lock errors:
1. Run `Remove-Item -Path "c:\Code\smart_tv_remote\build" -Recurse -Force`
2. Run `powershell.exe -ExecutionPolicy Bypass -File "c:\Code\smart_tv_remote\setup_and_build.ps1"`

## Generated Release APK Location
`C:\Code\smart_tv_remote\build\app\outputs\flutter-apk\app-release.apk`
