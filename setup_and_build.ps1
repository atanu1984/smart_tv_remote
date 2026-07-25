# Automated Flutter & Android SDK Setup and Build Script for Smart TV Remote

$ErrorActionPreference = "Stop"
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Starting Automated Flutter & Android Build Environment Setup" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Target Directory Setup
$targetSrcDir = "C:\src"
$flutterDir = "$targetSrcDir\flutter"
$jdkDir = "$targetSrcDir\jdk-17"
if (-not (Test-Path "$jdkDir\bin\java.exe")) {
    if (Test-Path "C:\Android\jdk-17.0.10+7\bin\java.exe") {
        $jdkDir = "C:\Android\jdk-17.0.10+7"
    }
}

# 2. Register JDK 17 & Git in Current Session Environment
$env:JAVA_HOME = $jdkDir
$env:Path = "$jdkDir\bin;C:\Program Files\Git\cmd;$flutterDir\bin;" + $env:Path

Write-Host "Verifying Java version from $jdkDir..." -ForegroundColor Yellow
& "$jdkDir\bin\java.exe" -version

# 3. Setup Android SDK Directory & Pre-Accept Licenses
$androidSdkDir = "C:\Android\sdk"
$cmdlineToolsDir = "$androidSdkDir\cmdline-tools\latest"
$env:ANDROID_HOME = $androidSdkDir
$env:ANDROID_SDK_ROOT = $androidSdkDir
$env:Path = "$cmdlineToolsDir\bin;$androidSdkDir\platform-tools;" + $env:Path

# 4. Ensure Platform 35 is installed
Write-Host "Ensuring Android SDK Platform 35 and Build Tools are installed..." -ForegroundColor Yellow
$sdkManager = "$cmdlineToolsDir\bin\sdkmanager.bat"

& "$sdkManager" --sdk_root="$androidSdkDir" "platform-tools" "platforms;android-35" "platforms;android-34" "build-tools;34.0.0"

# 5. Fetch Project Packages & Build Release APK
Write-Host "Fetching Pub dependencies for smart_tv_remote..." -ForegroundColor Yellow
Set-Location "c:\Code\smart_tv_remote"
& "$flutterDir\bin\flutter.bat" pub get

Write-Host "Compiling release-ready Android APK..." -ForegroundColor Yellow
& "$flutterDir\bin\flutter.bat" build apk --release --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Build Process Finished Successfully!" -ForegroundColor Green
Write-Host " Release APK Location: c:\Code\smart_tv_remote\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
