$ip = "192.168.0.213"
Write-Host "=== TESTING GOOGLE CAST VOLUME CONTROL ON TV ($ip:8008 / 8009) ===" -ForegroundColor Cyan

# Test HTTP POST to Port 8008
try {
    $url = "http://$ip:8008/apps/YouTube"
    $resp = Invoke-WebRequest -Uri $url -Method GET -TimeoutSec 2 -ErrorAction Stop
    Write-Host "[8008 HTTP] Google Cast REST responder active: $($resp.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "[8008 HTTP] $($_.Exception.Message)" -ForegroundColor Yellow
}
