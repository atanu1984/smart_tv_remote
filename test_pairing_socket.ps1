$ip = "192.168.0.213"
$port = 6467

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Testing TLS connection to ${ip}:${port}..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

try {
    $tcp = New-Object System.Net.Sockets.TcpClient($ip, $port)
    Write-Host "TCP Socket Connected to ${ip}:${port}" -ForegroundColor Green

    $sslStream = New-Object System.Net.Security.SslStream(
        $tcp.GetStream(),
        $false,
        ({ $true } -as [System.Net.Security.RemoteCertificateValidationCallback])
    )

    $sslStream.AuthenticateAsClient($ip)
    Write-Host "TLS Handshake Successful! IsEncrypted: $($sslStream.IsEncrypted)" -ForegroundColor Green

    # Build PairingRequest bytes (field 10)
    # Outer length prefix = 33
    # pairingMsg: version=2 (tag 0x08, val 0x02), status=OK (tag 0x10, val 0x01), PairingRequest tag 0x52
    [byte[]]$req = @(
        33, # length
        8, 2, # protocol_version = 2
        16, 1, # status = STATUS_OK (1)
        82, 27, # tag 0x52 (field 10, wire type 2), length 27
        10, 15, 97, 110, 100, 114, 111, 105, 100, 116, 118, 114, 101, 109, 111, 116, 101, 50, # service_name: "androidtvremote2"
        18, 8, 83, 109, 97, 114, 116, 32, 84, 86 # client_name: "Smart TV"
    )

    $sslStream.Write($req, 0, $req.Length)
    $sslStream.Flush()
    Write-Host "Sent PairingRequest payload ($( $req.Length ) bytes)" -ForegroundColor Yellow

    # Read response bytes from TV
    [byte[]]$buffer = New-Object byte[] 1024
    $bytesRead = $sslStream.Read($buffer, 0, $buffer.Length)

    Write-Host "Read $bytesRead bytes response from TV:" -ForegroundColor Cyan
    if ($bytesRead -gt 0) {
        $hex = ($buffer[0..($bytesRead-1)] | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        Write-Host "Response Hex: $hex" -ForegroundColor Green
    } else {
        Write-Host "TV closed connection without response" -ForegroundColor Red
    }

    $sslStream.Close()
    $tcp.Close()
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
