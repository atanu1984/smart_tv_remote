$ip = "192.168.0.213"

Write-Host "=== Deep TLS Diagnostic ===" -ForegroundColor Cyan

foreach ($port in @(6467, 6466)) {
    Write-Host "`n--- Port $port ---" -ForegroundColor Yellow
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($ip, $port)

        $certCallback = [System.Net.Security.RemoteCertificateValidationCallback]{
            param($sender, $cert, $chain, $errors)
            Write-Host "  [CERT CB] Errors: $errors" -ForegroundColor Magenta
            if ($cert) { Write-Host "  [CERT CB] Subject: $($cert.Subject)" -ForegroundColor Magenta }
            return $true
        }

        $sslStream = New-Object System.Net.Security.SslStream(
            $tcpClient.GetStream(),
            $false,
            $certCallback
        )

        try {
            $sslStream.AuthenticateAsClient(
                $ip,
                $null,
                [System.Security.Authentication.SslProtocols]::Tls12,
                $false
            )
            Write-Host "  TLS OK! Cipher: $($sslStream.CipherAlgorithm)" -ForegroundColor Green
        } catch {
            $inner = $_.Exception.InnerException
            Write-Host "  TLS FAIL (TLS1.2): $($_.Exception.Message)" -ForegroundColor Red
            if ($inner) { Write-Host "  Inner: $($inner.Message)" -ForegroundColor Red }

            # Try TLS 1.0
            try {
                $tcpClient2 = New-Object System.Net.Sockets.TcpClient
                $tcpClient2.Connect($ip, $port)
                $ssl2 = New-Object System.Net.Security.SslStream($tcpClient2.GetStream(), $false, $certCallback)
                $ssl2.AuthenticateAsClient(
                    $ip,
                    $null,
                    [System.Security.Authentication.SslProtocols]::Tls,
                    $false
                )
                Write-Host "  TLS 1.0 OK!" -ForegroundColor Green
                $ssl2.Close()
                $tcpClient2.Close()
            } catch {
                Write-Host "  TLS 1.0 also FAIL: $($_.Exception.Message)" -ForegroundColor DarkRed
            }
        }

        $tcpClient.Close()
    } catch {
        Write-Host "  TCP CONNECT FAIL on $port : $_" -ForegroundColor Red
    }
}
Write-Host "`nDone." -ForegroundColor Cyan
