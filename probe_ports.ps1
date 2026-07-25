$ip = "192.168.0.213"
$ports = @(6466, 6467, 8008, 8009, 8737, 8080, 8000, 4123, 1537, 5555, 8060, 8001)

Write-Host "Scanning TV ports at $ip..." -ForegroundColor Yellow

foreach ($port in $ports) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $async = $tcp.BeginConnect($ip, $port, $null, $null)
    $wait = $async.AsyncWaitHandle.WaitOne(400, $false)
    if ($wait) {
        try {
            $tcp.EndConnect($async)
            Write-Host "[OPEN] Port $port is active on TV" -ForegroundColor Green
        } catch {
            Write-Host "[CLOSED] Port $port" -ForegroundColor Gray
        } finally {
            $tcp.Close()
        }
    } else {
        $tcp.Close()
        Write-Host "[CLOSED] Port $port" -ForegroundColor Gray
    }
}
