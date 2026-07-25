$ip = "192.168.0.213"
Write-Host "=== Unpadded Modulus SHA-256 Pairing Secret Solver (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
$clientCert = $certCollection[0]

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

$tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
$callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
$sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
$sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
$serverCert = $sslStream.RemoteCertificate

Write-Host "  mTLS HANDSHAKE SUCCESSFUL!" -ForegroundColor Green

# 1. PairingRequest
[byte[]]$s = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$c = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$reqInner = @(10, $s.Length) + $s + @(18, $c.Length) + $c
[byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
[byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter
$sslStream.Write($req, 0, $req.Length); $sslStream.Flush()
$null = Read-ExactMsg $sslStream

# 2. PairingOption
[byte[]]$encodingMsg = @(8, 3, 16, 6) # type=3 HEXADECIMAL, len=6
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
$resp3 = Read-ExactMsg $sslStream

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ">>> 6-CHARACTER PIN POPUP IS NOW DISPLAYED ON YOUR TV SCREEN! <<<" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$pinInput = Read-Host "Type the 6-character PIN code from your TV screen and press ENTER"
$cleanPin = $pinInput.Trim().Replace("-", "").ToUpper()

# Extract RSA Modulus & Exponent (Unpadded)
$clientKeys = Get-RsaParamsUnpadded $clientCert
$serverKeys = Get-RsaParamsUnpadded $serverCert

Write-Host "Client Modulus Len: $($clientKeys.Modulus.Length), Exponent Len: $($clientKeys.Exponent.Length)" -ForegroundColor Gray
Write-Host "Server Modulus Len: $($serverKeys.Modulus.Length), Exponent Len: $($serverKeys.Exponent.Length)" -ForegroundColor Gray

[byte[]]$pinHexBytes = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $pinHexBytes[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

[byte[]]$pinAsciiBytes = [System.Text.Encoding]::UTF8.GetBytes($cleanPin)

# Hashing
$sha = [System.Security.Cryptography.SHA256]::Create()

# Form 1: SHA256(client_mod + client_exp + server_mod + server_exp + pinHexBytes)
[byte[]]$secret1 = $sha.ComputeHash($clientKeys.Modulus + $clientKeys.Exponent + $serverKeys.Modulus + $serverKeys.Exponent + $pinHexBytes)

# Form 2: SHA256(client_mod + client_exp + server_mod + server_exp + pinAsciiBytes)
[byte[]]$secret2 = $sha.ComputeHash($clientKeys.Modulus + $clientKeys.Exponent + $serverKeys.Modulus + $serverKeys.Exponent + $pinAsciiBytes)

# Form 3: SHA256(server_mod + server_exp + client_mod + client_exp + pinHexBytes)
[byte[]]$secret3 = $sha.ComputeHash($serverKeys.Modulus + $serverKeys.Exponent + $clientKeys.Modulus + $clientKeys.Exponent + $pinHexBytes)

# Form 4: SHA256(server_mod + server_exp + client_mod + client_exp + pinAsciiBytes)
[byte[]]$secret4 = $sha.ComputeHash($serverKeys.Modulus + $serverKeys.Exponent + $clientKeys.Modulus + $clientKeys.Exponent + $pinAsciiBytes)

function Send-SecretPayload([string]$name, [byte[]]$secretBytes) {
    Write-Host "`nSending $name ($($secretBytes.Length) bytes)..." -ForegroundColor Yellow
    [byte[]]$secretInner = @(10, $secretBytes.Length) + $secretBytes
    [byte[]]$secretOuter = @(8, 2, 16, 200, 1, 162, 2, $secretInner.Length) + $secretInner
    [byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter

    $sslStream.Write($secretMsg, 0, $secretMsg.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream 3500
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        Write-Host "  TV Response ($($resp.Length) bytes): $hex" -ForegroundColor Magenta
        if ($hex -match "10 C8 01" -or $hex -match "AA 02") {
            Write-Host "`n==========================================================" -ForegroundColor Green
            Write-Host ">>> MATCH SUCCESSFUL! $name STORED CERT ON TV! <<<" -ForegroundColor Green
            Write-Host "==========================================================" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  TV Response Status: Rejected ($hex)" -ForegroundColor Red
        }
    } else {
        Write-Host "  Timeout / Socket closed" -ForegroundColor DarkYellow
    }
    return $false
}

$ok = Send-SecretPayload -label "Form 1 (ClientKey + ServerKey + Hex PIN)" -secretBytes $secret1
if (-not $ok) { $ok = Send-SecretPayload -label "Form 2 (ClientKey + ServerKey + ASCII PIN)" -secretBytes $secret2 }
if (-not $ok) { $ok = Send-SecretPayload -label "Form 3 (ServerKey + ClientKey + Hex PIN)" -secretBytes $secret3 }
if (-not $ok) { $ok = Send-SecretPayload -label "Form 4 (ServerKey + ClientKey + ASCII PIN)" -secretBytes $secret4 }

Start-Sleep -Seconds 5
$sslStream.Close()
$tcpClient.Close()
