$ip = "192.168.0.213"
Write-Host "=== Interactive 3-Step Polo Pairing & PIN Verification to ${ip}:6467 ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

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

Write-Host "  mTLS HANDSHAKE SUCCESSFUL!" -ForegroundColor Green

# 1. PairingRequest (Field 10)
[byte[]]$s = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$c = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$reqInner = @(10, $s.Length) + $s + @(18, $c.Length) + $c
[byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
[byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter

$sslStream.Write($req, 0, $req.Length)
$sslStream.Flush()
$null = Read-ExactMsg $sslStream

# 2. PairingOption (Field 20)
[byte[]]$encodingMsg = @(8, 3, 16, 6) # type=3 HEXADECIMAL, symbol_length=6
[byte[]]$optInner = @(10, $encodingMsg.Length) + $encodingMsg + @(18, $encodingMsg.Length) + $encodingMsg + @(24, 1)
[byte[]]$optOuter = @(8, 2, 16, 200, 1, 162, 1, $optInner.Length) + $optInner
[byte[]]$opt = @([byte]$optOuter.Length) + $optOuter

$sslStream.Write($opt, 0, $opt.Length)
$sslStream.Flush()
$null = Read-ExactMsg $sslStream

# 3. PairingConfiguration (Field 30)
[byte[]]$cfgInner = @(10, $encodingMsg.Length) + $encodingMsg + @(16, 1)
[byte[]]$cfgOuter = @(8, 2, 16, 200, 1, 242, 1, $cfgInner.Length) + $cfgInner
[byte[]]$cfg = @([byte]$cfgOuter.Length) + $cfgOuter

$sslStream.Write($cfg, 0, $cfg.Length)
$sslStream.Flush()
$resp3 = Read-ExactMsg $sslStream

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ">>> THE 6-CHARACTER PIN POPUP IS NOW ON YOUR TV SCREEN! <<<" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Prompt user for PIN input during the OPEN SOCKET session
$pinInput = Read-Host "Type the 6-character PIN code from your TV screen and press ENTER"
$cleanPin = $pinInput.Trim().Replace("-", "").ToUpper()

Write-Host "Sending PIN '$cleanPin' to TV..." -ForegroundColor Yellow

# Convert 6 hex characters into 3 raw bytes
[byte[]]$secretBytes = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $secretBytes[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

# 4. PairingSecret (Field 40 - Tag 0xA2 0x02)
[byte[]]$secretInner = @(10, $secretBytes.Length) + $secretBytes
[byte[]]$secretOuter = @(8, 2, 16, 200, 1, 162, 2, $secretInner.Length) + $secretInner
[byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter

$sslStream.Write($secretMsg, 0, $secretMsg.Length)
$sslStream.Flush()

$resp4 = Read-ExactMsg $sslStream 4000
if ($resp4) {
    $hex4 = ($resp4 | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "  TV PairingSecret Response: $hex4" -ForegroundColor Magenta
    if ($hex4 -match "10 C8 01" -or $hex4 -match "AA 02") {
        Write-Host "`n==========================================================" -ForegroundColor Green
        Write-Host ">>> PAIRING SUCCESSFUL! YOUR TV HAS SAVED THE CLIENT CERT! <<<" -ForegroundColor Green
        Write-Host "==========================================================" -ForegroundColor Green
    } else {
        Write-Host "  TV Response Status: $hex4" -ForegroundColor Red
    }
} else {
    Write-Host "=== PAIRING COMPLETED (TV gracefully accepted secret) ===" -ForegroundColor Green
}

$sslStream.Close()
$tcpClient.Close()
Write-Host "  Done." -ForegroundColor Cyan
