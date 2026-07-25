param(
    [string]$pinInput = ""
)

$ip = "192.168.0.213"
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "=== EXACT LOUIS49 PROTOCOL PAIRING SECRET TESTER ===" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
$clientCert = $certCollection[0]

function Format-Hex([byte[]]$bytes) {
    if (-not $bytes -or $bytes.Length -eq 0) { return "<NONE>" }
    return ($bytes | ForEach-Object { "{0:X2}" -f $_ }) -join " "
}

function Decode-ProtobufStatus([byte[]]$bytes) {
    if (-not $bytes -or $bytes.Length -lt 3) { return "INVALID/EMPTY RESPONSE" }
    $hex = Format-Hex $bytes
    
    $statusStr = "UNKNOWN ($hex)"
    if ($hex -match "10 C8 01" -or $hex -match "AA 02") { $statusStr = "200 (STATUS_OK - PAIRING SUCCESSFUL! 🎉)" }
    elseif ($hex -match "10 90 03") { $statusStr = "400 (STATUS_BAD_CONFIGURATION)" }
    elseif ($hex -match "10 92 03" -or $hex -match "10 91 03") { $statusStr = "402 (STATUS_BAD_SECRET - Hash Mismatch)" }
    
    return $statusStr
}

function Read-ExactMsg($stream, [int]$timeoutMs = 3500) {
    if (-not $stream) { return $null }
    try {
        $stream.ReadTimeout = $timeoutMs
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

function Strip-LeadingZero([byte[]]$bytes) {
    if ($bytes.Length -gt 0 -and $bytes[0] -eq 0) {
        return $bytes[1..($bytes.Length - 1)]
    }
    return $bytes
}

function Get-RsaModulusAndExponent($cert) {
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
    $p = $rsa.ExportParameters($false)
    return @{
        Modulus = Strip-LeadingZero $p.Modulus
        Exponent = Strip-LeadingZero $p.Exponent
    }
}

# 1. Connect mTLS
Write-Host "`nConnecting to TV at ${ip}:6467..." -ForegroundColor Yellow
$tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
$callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
$sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
$sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
$serverCert = $sslStream.RemoteCertificate
Write-Host "  mTLS Handshake Connected!" -ForegroundColor Green

# Step 1: PairingRequest
[byte[]]$s = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$c = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$reqInner = @(10, $s.Length) + $s + @(18, $c.Length) + $c
[byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
[byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter
$sslStream.Write($req, 0, $req.Length); $sslStream.Flush()
$null = Read-ExactMsg $sslStream

# Step 2: PairingOption
[byte[]]$encodingMsg = @(8, 3, 16, 6)
[byte[]]$optInner = @(10, $encodingMsg.Length) + $encodingMsg + @(18, $encodingMsg.Length) + $encodingMsg + @(24, 1)
[byte[]]$optOuter = @(8, 2, 16, 200, 1, 162, 1, $optInner.Length) + $optInner
[byte[]]$opt = @([byte]$optOuter.Length) + $optOuter
$sslStream.Write($opt, 0, $opt.Length); $sslStream.Flush()
$null = Read-ExactMsg $sslStream

# Step 3: PairingConfiguration (triggers PIN on TV screen)
[byte[]]$cfgInner = @(10, $encodingMsg.Length) + $encodingMsg + @(16, 1)
[byte[]]$cfgOuter = @(8, 2, 16, 200, 1, 242, 1, $cfgInner.Length) + $cfgInner
[byte[]]$cfg = @([byte]$cfgOuter.Length) + $cfgOuter
$sslStream.Write($cfg, 0, $cfg.Length); $sslStream.Flush()
$null = Read-ExactMsg $sslStream

if (-not $pinInput) {
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host ">>> CHECK YOUR TV SCREEN NOW FOR THE 6-CHARACTER PIN! <<<" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    $pinInput = Read-Host "Type the 6-character PIN code currently on your TV screen and press ENTER"
}

$cleanPin = $pinInput.Trim().Replace("-", "").ToUpper()

# Extract RSA Modulus & Exponent
$cKey = Get-RsaModulusAndExponent $clientCert
$sKey = Get-RsaModulusAndExponent $serverCert

# Format exponent as [0x01, 0x00, 0x01] (3 bytes) and [0x00, 0x01, 0x00, 0x01] (4 bytes)
[byte[]]$cExp3 = $cKey.Exponent
[byte[]]$sExp3 = $sKey.Exponent
[byte[]]$cExp4 = if ($cExp3.Length -eq 3) { @(0x00) + $cExp3 } else { $cExp3 }
[byte[]]$sExp4 = if ($sExp3.Length -eq 3) { @(0x00) + $sExp3 } else { $sExp3 }

# Hex PIN bytes full (3 bytes, e.g. "C45BF6" -> [0xC4, 0x5B, 0xF6])
[byte[]]$pinHexFull = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $pinHexFull[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

# Hex PIN sliced (2 bytes, e.g. "5BF6" -> [0x5B, 0xF6])
$cleanPinSliced = $cleanPin.Substring(2)
[byte[]]$pinHexSliced = New-Object byte[] ($cleanPinSliced.Length / 2)
for ($i = 0; $i -lt $cleanPinSliced.Length; $i += 2) {
    $pinHexSliced[$i / 2] = [Convert]::ToByte($cleanPinSliced.Substring($i, 2), 16)
}

$sha = [System.Security.Cryptography.SHA256]::Create()

# Exact Louis49 candidate hashes:
# 1. Full Hex PIN + 3-byte Exponent
[byte[]]$h1 = $sha.ComputeHash($cKey.Modulus + $cExp3 + $sKey.Modulus + $sExp3 + $pinHexFull)

# 2. Sliced Hex PIN (4 chars) + 3-byte Exponent
[byte[]]$h2 = $sha.ComputeHash($cKey.Modulus + $cExp3 + $sKey.Modulus + $sExp3 + $pinHexSliced)

# 3. Full Hex PIN + 4-byte Exponent
[byte[]]$h3 = $sha.ComputeHash($cKey.Modulus + $cExp4 + $sKey.Modulus + $sExp4 + $pinHexFull)

# 4. Sliced Hex PIN (4 chars) + 4-byte Exponent
[byte[]]$h4 = $sha.ComputeHash($cKey.Modulus + $cExp4 + $sKey.Modulus + $sExp4 + $pinHexSliced)

Write-Host "`nTesting Louis49 Formula 1: Full Hex PIN ($cleanPin) + 3-byte Exponents..." -ForegroundColor Yellow
[byte[]]$secretInner1 = @(10, $h1.Length) + $h1
[byte[]]$secretOuter1 = @(8, 2, 16, 200, 1, 194, 2, $secretInner1.Length) + $secretInner1
[byte[]]$secretMsg1 = @([byte]$secretOuter1.Length) + $secretOuter1
$sslStream.Write($secretMsg1, 0, $secretMsg1.Length); $sslStream.Flush()

$resp1 = Read-ExactMsg $sslStream 3500
$resultText1 = Decode-ProtobufStatus $resp1
Write-Host "  Result: $resultText1" -ForegroundColor $(if ($resultText1 -match "200") { "Green" } else { "Red" })

if ($resultText1 -match "200") {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host ">>> SUCCESS! LOUIS49 FORMULA 1 ACCEPTED BY TV! <<<" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    $sslStream.Close(); $tcpClient.Close(); exit
}

# If rejected, test Formula 2 on sliced PIN
Write-Host "`nTesting Louis49 Formula 2: Sliced Hex PIN ($cleanPinSliced) + 3-byte Exponents..." -ForegroundColor Yellow
[byte[]]$secretInner2 = @(10, $h2.Length) + $h2
[byte[]]$secretOuter2 = @(8, 2, 16, 200, 1, 194, 2, $secretInner2.Length) + $secretInner2
[byte[]]$secretMsg2 = @([byte]$secretOuter2.Length) + $secretOuter2
$sslStream.Write($secretMsg2, 0, $secretMsg2.Length); $sslStream.Flush()

$resp2 = Read-ExactMsg $sslStream 3500
$resultText2 = Decode-ProtobufStatus $resp2
Write-Host "  Result: $resultText2" -ForegroundColor $(if ($resultText2 -match "200") { "Green" } else { "Red" })

if ($resultText2 -match "200") {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host ">>> SUCCESS! LOUIS49 FORMULA 2 ACCEPTED BY TV! <<<" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    $sslStream.Close(); $tcpClient.Close(); exit
}

$sslStream.Close()
$tcpClient.Close()
Write-Host "`nDone." -ForegroundColor Cyan
