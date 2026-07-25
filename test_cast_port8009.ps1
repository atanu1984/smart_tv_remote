$ip = "192.168.0.213"
$port = 8009

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Testing Google Cast TLS Connection on ${ip}:${port}..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

try {
    $tcp = New-Object System.Net.Sockets.TcpClient($ip, $port)
    Write-Host "TCP Connected to ${ip}:${port} ✅" -ForegroundColor Green

    $sslStream = New-Object System.Net.Security.SslStream(
        $tcp.GetStream(),
        $false,
        ({ $true } -as [System.Net.Security.RemoteCertificateValidationCallback])
    )

    $sslStream.AuthenticateAsClient($ip)
    Write-Host "TLS Handshake Successful on Port ${port}! IsEncrypted: $($sslStream.IsEncrypted)" -ForegroundColor Green

    # Send Google Cast CONNECT message over channel urn:x-cast:com.google.cast.tp.connection
    # Format: 4-byte big-endian length + CastMessage protobuf
    # CastMessage: protocol_version=0, source_id="sender-0", destination_id="receiver-0",
    # namespace="urn:x-cast:com.google.cast.tp.connection", payload_type=STRING, payload_utf8='{"type":"CONNECT"}'
    
    [byte[]]$payload = [System.Text.Encoding]::UTF8.GetBytes('{"type":"CONNECT"}')
    [byte[]]$header = @(
        0, 0, 0, 85, # outer length prefix
        8, 0, # protocol_version = 0
        18, 8, 115, 101, 110, 100, 101, 114, 45, 48, # source_id = "sender-0"
        26, 10, 114, 101, 99, 101, 105, 118, 101, 114, 45, 48, # destination_id = "receiver-0"
        34, 38, 117, 114, 110, 58, 120, 45, 99, 97, 115, 116, 58, 99, 111, 109, 46, 103, 111, 111, 103, 108, 101, 46, 99, 101, 115, 116, 46, 116, 112, 46, 99, 111, 110, 110, 101, 99, 116, 105, 111, 110, # namespace
        40, 0, # payload_type = STRING (0)
        50, 16, 123, 34, 116, 121, 112, 101, 34, 58, 34, 67, 79, 78, 78, 69, 67, 84, 34, 125 # payload_utf8 = '{"type":"CONNECT"}'
    )

    $sslStream.Write($header, 0, $header.Length)
    $sslStream.Flush()
    Write-Host "Sent Google Cast CONNECT payload to Port ${port}" -ForegroundColor Yellow

    # Read response
    [byte[]]$buffer = New-Object byte[] 1024
    $bytesRead = $sslStream.Read($buffer, 0, $buffer.Length)
    Write-Host "Read $bytesRead bytes response from Cast server!" -ForegroundColor Green

    $sslStream.Close()
    $tcp.Close()
} catch {
    Write-Host "Error on Port ${port}: $($_.Exception.Message)" -ForegroundColor Red
}
