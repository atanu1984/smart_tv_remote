$ip = "192.168.0.213"
Write-Host "=== Testing Encoding Types for PairingConfiguration (${ip}:6467) ===" -ForegroundColor Cyan

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

function Test-Type([string]$label, [int]$typeVal) {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)

    # 1. Send PairingRequest
    [byte[]]$serviceBytes = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
    [byte[]]$clientBytes  = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
    [byte[]]$reqInner = @(10, $serviceBytes.Length) + $serviceBytes + @(18, $clientBytes.Length) + $clientBytes
    [byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
    [byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter

    $sslStream.Write($req, 0, $req.Length)
    $sslStream.Flush()
    $null = Read-ExactMsg $sslStream

    # 2. Build PairingConfiguration with specified typeVal
    [byte[]]$encoding = @(8, $typeVal, 16, 6) # type=$typeVal, symbol_length=6
    [byte[]]$inputEnc = @(10, $encoding.Length) + $encoding # field 1 (input_encodings)
    [byte[]]$outputEnc = @(18, $encoding.Length) + $encoding # field 2 (output_encodings)
    [byte[]]$role = @(24, 1) # field 3 (preferred_role = 1)

    [byte[]]$configInner = $inputEnc + $outputEnc + $role
    [byte[]]$configOuter = @(8, 2, 16, 200, 1, 242, 1, $configInner.Length) + $configInner
    [byte[]]$config = @([byte]$configOuter.Length) + $configOuter

    $sslStream.Write($config, 0, $config.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        if ($hex -match "10 C8 01") {
            Write-Host "`nSUCCESS! $label returned [STATUS_OK 200]!" -ForegroundColor Green
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

Test-Type -label "Type 1: ALPHANUMERIC" -typeVal 1
Test-Type -label "Type 2: NUMERIC" -typeVal 2
Test-Type -label "Type 3: HEXADECIMAL" -typeVal 3
