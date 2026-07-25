$ip = "192.168.0.213"
Write-Host "=== PairingConfiguration Matrix Solver (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

function Read-ExactMsg($stream) {
    [byte[]]$lenBuf = New-Object byte[] 1
    $n = $stream.Read($lenBuf, 0, 1)
    if ($n -eq 0) { return $null }
    $msgLen = $lenBuf[0]
    [byte[]]$bodyBuf = New-Object byte[] $msgLen
    $readSoFar = 0
    while ($readSoFar -lt $msgLen) {
        $r = $stream.Read($bodyBuf, $readSoFar, $msgLen - $readSoFar)
        if ($r -le 0) { break }
        $readSoFar += $r
    }
    return @($lenBuf[0]) + $bodyBuf
}

function Test-ConfigPayload([string]$label, [byte[]]$configInner) {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)

    # 1. PairingRequest
    [byte[]]$serviceBytes = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
    [byte[]]$clientBytes  = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
    [byte[]]$reqInner = @(10, $serviceBytes.Length) + $serviceBytes + @(18, $clientBytes.Length) + $clientBytes
    [byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
    [byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter

    $sslStream.Write($req, 0, $req.Length)
    $sslStream.Flush()
    $null = Read-ExactMsg $sslStream

    # 2. PairingConfiguration
    [byte[]]$configOuter = @(8, 2, 16, 200, 1, 242, 1, $configInner.Length) + $configInner
    [byte[]]$config = @([byte]$configOuter.Length) + $configOuter

    $sslStream.Write($config, 0, $config.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        if ($hex -match "10 C8 01") {
            Write-Host "  SUCCESS! [STATUS_OK 200] -> $label" -ForegroundColor Green
            Write-Host "  TV Response: $hex" -ForegroundColor Green
            Write-Host "`n>>> CHECK TV SCREEN NOW FOR 6-DIGIT PIN POPUP <<<" -ForegroundColor Cyan
            Start-Sleep -Seconds 10
        } else {
            Write-Host "  FAILED [STATUS_ERROR 400 ($hex)] -> $label" -ForegroundColor Red
        }
    } else {
        Write-Host "  TIMEOUT -> $label" -ForegroundColor DarkYellow
    }

    $sslStream.Close()
    $tcpClient.Close()
}

# Test Candidate 1: Field 1 encoding (type=2 NUMERIC, len=6), Field 2 role=1
Test-ConfigPayload -label "Candidate 1: encoding(type=2 NUMERIC, len=6), role=1" -configInner @(10, 4, 8, 2, 16, 6, 16, 1)

# Test Candidate 2: Field 1 encoding (type=1 ALPHANUMERIC, len=6), Field 2 role=1
Test-ConfigPayload -label "Candidate 2: encoding(type=1 ALPHANUMERIC, len=6), role=1" -configInner @(10, 4, 8, 1, 16, 6, 16, 1)

# Test Candidate 3: Field 1 encoding (type=2 NUMERIC, len=4), Field 2 role=1
Test-ConfigPayload -label "Candidate 3: encoding(type=2 NUMERIC, len=4), role=1" -configInner @(10, 4, 8, 2, 16, 4, 16, 1)

# Test Candidate 4: Field 1 role=1 (0x08 0x01), Field 2 encoding (0x12, 4, 8, 2, 16, 6)
Test-ConfigPayload -label "Candidate 4: role=1 (0x08), encoding(type=2 NUMERIC, len=6) (0x12)" -configInner @(8, 1, 18, 4, 8, 2, 16, 6)

# Test Candidate 5: Field 1 encoding (type=2 NUMERIC, len=6) ONLY (no role tag)
Test-ConfigPayload -label "Candidate 5: encoding(type=2 NUMERIC, len=6) ONLY" -configInner @(10, 4, 8, 2, 16, 6)

# Test Candidate 6: Field 1 encoding (type=1 ALPHANUMERIC, len=6) ONLY (no role tag)
Test-ConfigPayload -label "Candidate 6: encoding(type=1 ALPHANUMERIC, len=6) ONLY" -configInner @(10, 4, 8, 1, 16, 6)
