$ip = "192.168.0.213"

# Test 1: Plain TLS to port 6467 (pairing port)
Write-Host "`n=== TLS Test Port 6467 (Pairing) ===" -ForegroundColor Cyan
try {
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip)
    Write-Host "  TLS HANDSHAKE OK on port 6467" -ForegroundColor Green
    Write-Host "  Server Cert Subject: $($sslStream.RemoteCertificate.Subject)" -ForegroundColor Yellow
    Write-Host "  Server Cert Issuer : $($sslStream.RemoteCertificate.Issuer)" -ForegroundColor Yellow

    # Send a raw PairingRequest proto payload (length prefixed)
    # field1=version(2), field2=status(1), field10=PairingRequest{field1=serviceName,field2=clientName}
    $serviceBytes = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
    $clientBytes  = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
    $inner = @(0x0A, $serviceBytes.Length) + $serviceBytes + @(0x12, $clientBytes.Length) + $clientBytes
    $outer = @(0x08, 0x02, 0x10, 0x01, 0x52, $inner.Count) + $inner
    $msg   = @([byte]$outer.Count) + $outer
    $sslStream.Write([byte[]]$msg, 0, $msg.Length)
    $sslStream.Flush()
    Write-Host "  PairingRequest sent ($($msg.Length) bytes)" -ForegroundColor Green

    # Wait for response
    $buf = New-Object byte[] 256
    $sslStream.ReadTimeout = 3000
    try {
        $n = $sslStream.Read($buf, 0, 256)
        Write-Host "  TV Response ($n bytes): $([BitConverter]::ToString($buf[0..([Math]::Min($n-1,31))]))" -ForegroundColor Magenta
    } catch { Write-Host "  No response / timeout" -ForegroundColor DarkYellow }
    $sslStream.Close()
    $tcpClient.Close()
} catch {
    Write-Host "  FAILED on 6467: $_" -ForegroundColor Red
}

# Test 2: Plain TLS to port 6466 (command port)
Write-Host "`n=== TLS Test Port 6466 (Commands) ===" -ForegroundColor Cyan
try {
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6466)
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip)
    Write-Host "  TLS HANDSHAKE OK on port 6466" -ForegroundColor Green
    Write-Host "  Server Cert Subject: $($sslStream.RemoteCertificate.Subject)" -ForegroundColor Yellow

    # Wait for RemoteStart message
    $buf = New-Object byte[] 256
    $sslStream.ReadTimeout = 4000
    try {
        $n = $sslStream.Read($buf, 0, 256)
        Write-Host "  TV Initial Message ($n bytes): $([BitConverter]::ToString($buf[0..([Math]::Min($n-1,31))]))" -ForegroundColor Magenta
        Write-Host "  ASCII: $([System.Text.Encoding]::ASCII.GetString($buf[0..([Math]::Min($n-1,31))]))" -ForegroundColor Magenta
    } catch { Write-Host "  No initial message / timeout (TV may need client cert to send RemoteStart)" -ForegroundColor DarkYellow }
    $sslStream.Close()
    $tcpClient.Close()
} catch {
    Write-Host "  FAILED on 6466: $_" -ForegroundColor Red
}
Write-Host "`nDone." -ForegroundColor Cyan
