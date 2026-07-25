$ip = "192.168.0.213"
Write-Host "=== Polo Secret Solver with Session Reconnection (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
$clientCert = $certCollection[0]

function Read-ExactMsg($stream, [int]$timeoutMs = 3000) {
    $stream.ReadTimeout = $timeoutMs
    try {
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
    } catch {
        return $null
    }
}

function Strip-LeadingZeros([byte[]]$bytes) {
    $start = 0
    while ($start -lt $bytes.Length - 1 -and $bytes[$start] -eq 0) {
        $start++
    }
    if ($start -eq 0) { return $bytes }
    return $bytes[$start..($bytes.Length - 1)]
}

function Get-RsaParamsUnpadded($cert) {
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
    $p = $rsa.ExportParameters($false)
    return @{
        Modulus  = Strip-LeadingZeros $p.Modulus
        Exponent = Strip-LeadingZeros $p.Exponent
    }
}

function Perform-Handshake() {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
    $serverCert = $sslStream.RemoteCertificate

    # 1. PairingRequest
    [byte[]]$s = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
    [byte[]]$c = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
    [byte[]]$reqInner = @(10, $s.Length) + $s + @(18, $c.Length) + $c
    [byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
    [byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter
    $sslStream.Write($req, 0, $req.Length); $sslStream.Flush()
    $null = Read-ExactMsg $sslStream

    # 2. PairingOption
    [byte[]]$encodingMsg = @(8, 3, 16, 6)
    [byte[]]$optInner = @(10, $encodingMsg.Length) + $encodingMsg + @(18, $encodingMsg.Length) + $encodingMsg + @(24, 1)
    [byte[]]$optOuter = @(8, 2, 16, 200, 1, 162, 1, $optInner.Length) + $optInner
    [byte[]]$opt = @([byte]$optOuter.Length) + $optOuter
    $sslStream.Write($opt, 0, $opt.Length); $sslStream.Flush()
    $null = Read-ExactMsg $sslStream

    # 3. PairingConfiguration
    [byte[]]$cfgInner = @(10, $encodingMsg.Length) + $encodingMsg + @(16, 1)
    [byte[]]$cfgOuter = @(8, 2, 16, 200, 1, 242, 1, $cfgInner.Length) + $cfgInner
    [byte[]]$cfg = @([byte]$cfgOuter.Length) + $cfgOuter
    $sslStream.Write($cfg, 0, $cfg.Length); $sslStream.Flush()
    $null = Read-ExactMsg $sslStream

    return @{
        TcpClient  = $tcpClient
        SslStream  = $sslStream
        ServerCert = $serverCert
    }
}

$sess = Perform-Handshake
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ">>> 6-CHARACTER PIN POPUP IS NOW DISPLAYED ON YOUR TV SCREEN! <<<" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$pinInput = Read-Host "Type the 6-character PIN code from your TV screen and press ENTER"
$cleanPin = $pinInput.Trim().Replace("-", "").ToUpper()

[byte[]]$pinHex = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $pinHex[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}
[byte[]]$pinAscii = [System.Text.Encoding]::UTF8.GetBytes($cleanPin)

$sha = [System.Security.Cryptography.SHA256]::Create()

function Test-SingleFormula([string]$label, [byte[]]$secretBytes, [ref]$currentSessRef) {
    Write-Host "`nTesting $label ($($secretBytes.Length) bytes)..." -ForegroundColor Yellow
    
    $stream = $currentSessRef.Value.SslStream
    [byte[]]$secretInner = @(10, $secretBytes.Length) + $secretBytes
    [byte[]]$secretOuter = @(8, 2, 16, 200, 1, 162, 2, $secretInner.Length) + $secretInner
    [byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter

    try {
        $stream.Write($secretMsg, 0, $secretMsg.Length)
        $stream.Flush()
        $resp = Read-ExactMsg $stream 3000
        if ($resp) {
            $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
            Write-Host "  TV Response ($($resp.Length) bytes): $hex" -ForegroundColor Magenta
            if ($hex -match "10 C8 01" -or $hex -match "AA 02" -or $hex -match "10 08 01") {
                Write-Host "`n==========================================================" -ForegroundColor Green
                Write-Host ">>> MATCH SUCCESSFUL! $label ACCEPTED BY TV! <<<" -ForegroundColor Green
                Write-Host "==========================================================" -ForegroundColor Green
                return $true
            } else {
                Write-Host "  TV Rejected ($hex)" -ForegroundColor Red
            }
        } else {
            Write-Host "  Timeout / Socket closed" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "  Write Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # TV closes socket on failure; reconnect for next attempt
    try { $currentSessRef.Value.SslStream.Close(); $currentSessRef.Value.TcpClient.Close() } catch {}
    Start-Sleep -Milliseconds 300
    $currentSessRef.Value = Perform-Handshake
    return $false
}

$sessRef = [ref]$sess

# Build candidate secrets with current session certs
$clientKeys = Get-RsaParamsUnpadded $clientCert
$serverKeys = Get-RsaParamsUnpadded $sess.ServerCert

# Formula A: Polo SHA256 (ClientMod + ClientExp + ServerMod + ServerExp + PinHex)
[byte[]]$candA = $sha.ComputeHash($clientKeys.Modulus + $clientKeys.Exponent + $serverKeys.Modulus + $serverKeys.Exponent + $pinHex)

# Formula B: Polo SHA256 (ClientMod + ClientExp + ServerMod + ServerExp + PinAscii)
[byte[]]$candB = $sha.ComputeHash($clientKeys.Modulus + $clientKeys.Exponent + $serverKeys.Modulus + $serverKeys.Exponent + $pinAscii)

# Formula C: Polo SHA256 (ServerMod + ServerExp + ClientMod + ClientExp + PinHex)
[byte[]]$candC = $sha.ComputeHash($serverKeys.Modulus + $serverKeys.Exponent + $clientKeys.Modulus + $clientKeys.Exponent + $pinHex)

# Formula D: Polo SHA256 (ServerMod + ServerExp + ClientMod + ClientExp + PinAscii)
[byte[]]$candD = $sha.ComputeHash($serverKeys.Modulus + $serverKeys.Exponent + $clientKeys.Modulus + $clientKeys.Exponent + $pinAscii)

$ok = Test-SingleFormula -label "Formula A (Client RSA + Server RSA + PinHex SHA256)" -secretBytes $candA -currentSessRef $sessRef
if (-not $ok) { $ok = Test-SingleFormula -label "Formula B (Client RSA + Server RSA + PinAscii SHA256)" -secretBytes $candB -currentSessRef $sessRef }
if (-not $ok) { $ok = Test-SingleFormula -label "Formula C (Server RSA + Client RSA + PinHex SHA256)" -secretBytes $candC -currentSessRef $sessRef }
if (-not $ok) { $ok = Test-SingleFormula -label "Formula D (Server RSA + Client RSA + PinAscii SHA256)" -secretBytes $candD -currentSessRef $sessRef }

try { $sessRef.Value.SslStream.Close(); $sessRef.Value.TcpClient.Close() } catch {}
Write-Host "`nDone." -ForegroundColor Cyan
