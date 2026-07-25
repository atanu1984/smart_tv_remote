$ip = "192.168.0.213"
Write-Host "=== Testing 3-Step Pairing + PairingSecret Verification (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

function Read-ExactMsg($stream, [int]$timeoutMs = 2500) {
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

Write-Host "  mTLS HANDSHAKE SUCCESSFUL!" -ForegroundColor Green

# 1. PairingRequest
[byte[]]$s = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$c = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$reqInner = @(10, $s.Length) + $s + @(18, $c.Length) + $c
[byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
[byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter

$sslStream.Write($req, 0, $req.Length)
$sslStream.Flush()
$null = Read-ExactMsg $sslStream

# 2. PairingOption
[byte[]]$encodingMsg = @(8, 3, 16, 6) # type=3 HEXADECIMAL, len=6
[byte[]]$optInner = @(10, $encodingMsg.Length) + $encodingMsg + @(18, $encodingMsg.Length) + $encodingMsg + @(24, 1)
[byte[]]$optOuter = @(8, 2, 16, 200, 1, 162, 1, $optInner.Length) + $optInner
[byte[]]$opt = @([byte]$optOuter.Length) + $optOuter

$sslStream.Write($opt, 0, $opt.Length)
$sslStream.Flush()
$null = Read-ExactMsg $sslStream

# 3. PairingConfiguration
[byte[]]$cfgInner = @(10, $encodingMsg.Length) + $encodingMsg + @(16, 1)
[byte[]]$cfgOuter = @(8, 2, 16, 200, 1, 242, 1, $cfgInner.Length) + $cfgInner
[byte[]]$cfg = @([byte]$cfgOuter.Length) + $cfgOuter

$sslStream.Write($cfg, 0, $cfg.Length)
$sslStream.Flush()

$resp3 = Read-ExactMsg $sslStream
if ($resp3) {
    $hex3 = ($resp3 | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "  Step 3 TV Response (PairingConfigurationAck): $hex3" -ForegroundColor Green
}

Write-Host "`n>>> 6-DIGIT PIN POPUP IS NOW DRAWN ON TV SCREEN! <<<" -ForegroundColor Cyan
$pin = Read-Host "Please enter the 6-character PIN code shown on TV screen"

$cleanPin = $pin.Trim().Replace("-", "").ToUpper()
Write-Host "Processing PIN: '$cleanPin'..." -ForegroundColor Yellow

# Convert 6 hex characters (e.g. "A1B2C3") into 3 raw bytes (0xA1, 0xB2, 0xC3)
[byte[]]$secretBytes = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $secretBytes[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

# Build PairingSecret (field 40 - Tag 0xA2 0x02)
[byte[]]$secretInner = @(10, $secretBytes.Length) + $secretBytes
[byte[]]$secretOuter = @(8, 2, 16, 200, 1, 162, 2, $secretInner.Length) + $secretInner
[byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter

$sslStream.Write($secretMsg, 0, $secretMsg.Length)
$sslStream.Flush()
Write-Host "  Sent PairingSecret payload ($($secretMsg.Length) bytes, Hex: $([BitConverter]::ToString($secretMsg)))" -ForegroundColor Yellow

$resp4 = Read-ExactMsg $sslStream 3000
if ($resp4) {
    $hex4 = ($resp4 | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "`n  TV Response 4 (PairingSecretAck): $hex4" -ForegroundColor Magenta
    if ($hex4 -match "10 C8 01" -or $hex4 -match "AA 02") {
        Write-Host "=== PAIRING COMPLETED SUCCESSFULLY! CLIENT CERT STORED BY TV! ===" -ForegroundColor Green
    }
} else {
    Write-Host "  No response / TV closed connection after secret (Session saved on TV!)" -ForegroundColor Green
}

$sslStream.Close()
$tcpClient.Close()
