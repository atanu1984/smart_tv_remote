$ip = "192.168.0.213"
Write-Host "=== Testing Status Tag variations in PairingConfiguration (${ip}:6467) ===" -ForegroundColor Cyan

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

function Test-StatusHeader([string]$label, [byte[]]$pairingMsg) {
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
    [byte[]]$config = @([byte]$pairingMsg.Length) + $pairingMsg
    $sslStream.Write($config, 0, $config.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        if ($hex -match "10 C8 01" -or $hex -match "FA 01") {
            Write-Host "`nSUCCESS! $label returned SUCCESS!" -ForegroundColor Green
            Write-Host "TV Response ($($resp.Length) bytes): $hex" -ForegroundColor Green
            Write-Host "`n>>> CHECK TV SCREEN NOW FOR 6-DIGIT PIN POPUP <<<" -ForegroundColor Cyan
            Start-Sleep -Seconds 15
        } else {
            Write-Host "FAILED [Response: $hex] -> $label" -ForegroundColor Red
        }
    } else {
        Write-Host "TIMEOUT -> $label" -ForegroundColor DarkYellow
    }

    $sslStream.Close()
    $tcpClient.Close()
}

[byte[]]$configInner = @(10, 4, 8, 2, 16, 6, 16, 1) # encoding(type=2, len=6), role=1

# Variant A: protocol_version=2, status=STATUS_OK(200) [8,2, 16,200,1, 242,1, len, inner]
Test-StatusHeader -label "Variant A: status=STATUS_OK (200)" -pairingMsg (@(8, 2, 16, 200, 1, 242, 1, $configInner.Length) + $configInner)

# Variant B: protocol_version=2, status=STATUS_UNKNOWN(0) [8,2, 16,0, 242,1, len, inner]
Test-StatusHeader -label "Variant B: status=STATUS_UNKNOWN (0)" -pairingMsg (@(8, 2, 16, 0, 242, 1, $configInner.Length) + $configInner)

# Variant C: protocol_version=2, status omitted [8,2, 242,1, len, inner]
Test-StatusHeader -label "Variant C: status omitted" -pairingMsg (@(8, 2, 242, 1, $configInner.Length) + $configInner)

# Variant D: protocol_version=2, status=STATUS_OK(200), field 30 wrapped with field 2 encoding
[byte[]]$configInner2 = @(18, 4, 8, 2, 16, 6, 16, 1) # field 2 (0x12) encoding
Test-StatusHeader -label "Variant D: field 2 encoding (0x12) + role=1" -pairingMsg (@(8, 2, 16, 200, 1, 242, 1, $configInner2.Length) + $configInner2)
