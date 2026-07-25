$ip = "192.168.0.213"
Write-Host "=== Raw SSL Hello Test ===" -ForegroundColor Cyan
foreach ($port in @(6467, 6466)) {
    Write-Host "`n--- Port $port ---" -ForegroundColor Yellow
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($ip, $port)
        $stream = $tcpClient.GetStream()
        $stream.ReadTimeout = 3000

        # Send a TLS ClientHello manually (raw bytes) and read what TV responds with
        # This is a minimal TLS 1.0 ClientHello
        $clientHello = [byte[]](
            0x16, 0x03, 0x01, 0x00, 0x2f,   # Record Layer: Handshake, TLS1.0, length=47
            0x01, 0x00, 0x00, 0x2b,           # ClientHello, length=43
            0x03, 0x03,                        # TLS 1.2
            # 32 bytes random
            0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,
            0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f,
            0x00,                              # Session ID length
            0x00, 0x04,                        # Cipher suites length=4
            0x00, 0x2f,                        # TLS_RSA_WITH_AES_128_CBC_SHA
            0x00, 0x35,                        # TLS_RSA_WITH_AES_256_CBC_SHA
            0x01, 0x00                         # Compression: null
        )
        $stream.Write($clientHello, 0, $clientHello.Length)
        Write-Host "  Sent TLS ClientHello" -ForegroundColor Green

        $buf = New-Object byte[] 512
        try {
            $n = $stream.Read($buf, 0, 512)
            $hex = [BitConverter]::ToString($buf[0..([Math]::Min($n-1, 31))])
            Write-Host "  TV Responded ($n bytes): $hex" -ForegroundColor Magenta
            # If first byte is 0x15 = Alert, second/third = TLS version, 4th = fatal, 5th = error code
            if ($buf[0] -eq 0x15) {
                $alertCode = $buf[6]
                $alertMeaning = switch ($alertCode) {
                    40 { "handshake_failure (missing client cert?)" }
                    42 { "bad_certificate (client cert required)" }
                    43 { "unsupported_certificate" }
                    44 { "certificate_revoked" }
                    70 { "protocol_version (TLS version mismatch)" }
                    default { "code=$alertCode" }
                }
                Write-Host "  >> TLS Alert: $alertMeaning" -ForegroundColor Red
            } elseif ($buf[0] -eq 0x16) {
                Write-Host "  >> TLS Handshake message (ServerHello) - TV accepts plain TLS!" -ForegroundColor Green
            }
        } catch { Write-Host "  No response / timeout" -ForegroundColor DarkYellow }

        $tcpClient.Close()
    } catch { Write-Host "  Failed: $_" -ForegroundColor Red }
}
