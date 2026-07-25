$ip = "192.168.0.213"
$port = 8008
$paths = @(
    "/remote/media_control?action=key&value=volumeup",
    "/?action=key&code=24",
    "/keypress/volumeup",
    "/system/control",
    "/apps/YouTube",
    "/setup/configured_networks",
    "/ssdp/device-desc.xml"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Testing GET paths on ${ip}:${port}" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

foreach ($p in $paths) {
    $url = "http://${ip}:${port}${p}"
    try {
        $resp = Invoke-WebRequest -Uri $url -TimeoutSec 2 -ErrorAction Stop
        Write-Host "GET $p -> Status: $($resp.StatusCode)" -ForegroundColor Green
    } catch {
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            Write-Host "GET $p -> HTTP $code" -ForegroundColor Yellow
        } else {
            Write-Host "GET $p -> FAILED ($($_.Exception.Message))" -ForegroundColor Red
        }
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Testing POST paths on ${ip}:${port}" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

foreach ($p in $paths) {
    $url = "http://${ip}:${port}${p}"
    try {
        $resp = Invoke-WebRequest -Uri $url -Method Post -TimeoutSec 2 -ErrorAction Stop
        Write-Host "POST $p -> Status: $($resp.StatusCode)" -ForegroundColor Green
    } catch {
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            Write-Host "POST $p -> HTTP $code" -ForegroundColor Yellow
        } else {
            Write-Host "POST $p -> FAILED ($($_.Exception.Message))" -ForegroundColor Red
        }
    }
}
