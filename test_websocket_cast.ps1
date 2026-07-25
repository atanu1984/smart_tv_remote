$ip = "192.168.0.213"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Testing WebSockets & Endpoints on $ip" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Test DIAL Application URL from device-desc.xml
try {
    $xmlResp = Invoke-WebRequest -Uri "http://${ip}:8008/ssdp/device-desc.xml" -TimeoutSec 2
    [xml]$xml = $xmlResp.Content
    Write-Host "Device FriendlyName: $($xml.root.device.friendlyName)" -ForegroundColor Green
    Write-Host "Manufacturer: $($xml.root.device.manufacturer)" -ForegroundColor Green
    Write-Host "Model: $($xml.root.device.modelName)" -ForegroundColor Green
    Write-Host "UDN: $($xml.root.device.UDN)" -ForegroundColor Green
} catch {
    Write-Host "XML fetch error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test WebSocket connection to port 8008 / 8009
try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource(2000)
    $uri = New-Object System.Uri("ws://${ip}:8008/")
    $ws.ConnectAsync($uri, $cts.Token).Wait()
    if ($ws.State -eq 'Open') {
        Write-Host "WebSocket OPEN on ws://${ip}:8008/" -ForegroundColor Green
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).Wait()
    }
} catch {
    Write-Host "ws://${ip}:8008/ failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test WebSocket connection to port 8008/system/control
try {
    $ws2 = New-Object System.Net.WebSockets.ClientWebSocket
    $cts2 = New-Object System.Threading.CancellationTokenSource(2000)
    $uri2 = New-Object System.Uri("ws://${ip}:8008/system/control")
    $ws2.ConnectAsync($uri2, $cts2.Token).Wait()
    if ($ws2.State -eq 'Open') {
        Write-Host "WebSocket OPEN on ws://${ip}:8008/system/control" -ForegroundColor Green
        $ws2.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts2.Token).Wait()
    }
} catch {
    Write-Host "ws://${ip}:8008/system/control failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
