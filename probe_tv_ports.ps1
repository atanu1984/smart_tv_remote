$ports = @(6466, 6467, 8737, 8008, 8009, 5555, 8060, 8001, 8080, 8000, 1537, 3000, 9080)
$ip = "192.168.0.213"
Write-Host "Probing $ip for open ports..." -ForegroundColor Cyan
foreach ($p in $ports) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect($ip, $p, $null, $null)
        $wait = $conn.AsyncWaitHandle.WaitOne(800, $false)
        if ($wait -and $tcp.Connected) {
            Write-Host "  OPEN  : Port $p" -ForegroundColor Green
        } else {
            Write-Host "  CLOSED: Port $p" -ForegroundColor DarkGray
        }
        $tcp.Close()
    } catch {
        Write-Host "  ERROR : Port $p - $_" -ForegroundColor Red
    }
}
Write-Host "Done." -ForegroundColor Cyan
