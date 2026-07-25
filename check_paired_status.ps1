Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "=== VERIFYING IF CERTIFICATE IS REALLY PAIRED ON YOUR TV ===" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ipAddress = "192.168.0.213"
$targetPort = "6466"

Write-Host "Testing mTLS connection to TV Control Port ($ipAddress on port $targetPort)..." -ForegroundColor Yellow

C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe "C:\Code\smart_tv_remote\test_control_port6466.dart"
