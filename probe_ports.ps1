$ip = "192.168.0.213"
$ports = @(6466, 6467, 8008, 8009, 4123, 8737, 5555, 8000, 8080)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Probing All Known TCL TV Control Ports on $ip" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

foreach ($p in $ports) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($ip, $p, $null, $null)
        $success = $iar.AsyncWaitHandle.WaitOne(300, $false)
        if ($success -and $client.Connected) {
            Write-Host "Port ${p}: OPEN ✅" -ForegroundColor Green
            $client.Close()
        } else {
            Write-Host "Port ${p}: CLOSED" -ForegroundColor Red
            $client.Close()
        }
    } catch {
        Write-Host "Port ${p}: CLOSED" -ForegroundColor Red
    }
}
