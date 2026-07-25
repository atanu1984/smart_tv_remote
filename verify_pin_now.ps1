param(
    [string]$pinCode = "84B6D5"
)

$ip = "192.168.0.213"
Write-Host "=== Live PIN Verification Tester for PIN '$pinCode' (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
$clientCert = $certCollection[0]

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

$cleanPin = $pinCode.Trim().Replace("-", "").ToUpper()
Write-Host "  Step 3 complete. Testing PIN '$cleanPin'..." -ForegroundColor Yellow

# Formats to test
[byte[]]$secretASCII = [System.Text.Encoding]::UTF8.GetBytes($cleanPin)

[byte[]]$secretHex = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $secretHex[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

$sha = [System.Security.Cryptography.SHA256]::Create()
[byte[]]$clientRaw = $clientCert.GetRawCertData()
[byte[]]$serverRaw = $serverCert.GetRawCertData()

[byte[]]$secretSHA_Hex = $sha.ComputeHash($clientRaw + $serverRaw + $secretHex)
[byte[]]$secretSHA_ASCII = $sha.ComputeHash($clientRaw + $serverRaw + $secretASCII)

function Send-SecretPayload([string]$name, [byte[]]$secretBytes) {
    Write-Host "`n  Testing Secret Format: $name ($($secretBytes.Length) bytes)..." -ForegroundColor Yellow
    [byte[]]$secretInner = @(10, $secretBytes.Length) + $secretBytes
    [byte[]]$secretOuter = @(8, 2, 16, 200, 1, 162, 2, $secretInner.Length) + $secretInner
    [byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter

    $sslStream.Write($secretMsg, 0, $secretMsg.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream 2000
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        Write-Host "  TV Response ($($resp.Length) bytes): $hex" -ForegroundColor Magenta
        if ($hex -match "10 C8 01" -or $hex -match "AA 02") {
            Write-Host "`n==========================================================" -ForegroundColor Green
            Write-Host ">>> SUCCESS! $name PAIRING ACCEPTED BY TV! <<<" -ForegroundColor Green
            Write-Host "==========================================================" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  TV Response Status: Rejected ($hex)" -ForegroundColor Red
        }
    } else {
        Write-Host "  Timeout / TV closed socket" -ForegroundColor DarkYellow
    }
    return $false
}

$done = Send-SecretPayload -name "Format 1: Raw Hex Bytes [0x84, 0xB6, 0xD5]" -secretBytes $secretHex
if (-not $done) { $done = Send-SecretPayload -name "Format 2: ASCII String Bytes '84B6D5'" -secretBytes $secretASCII }
if (-not $done) { $done = Send-SecretPayload -name "Format 3: SHA256(Certs + Hex)" -secretBytes $secretSHA_Hex }
if (-not $done) { $done = Send-SecretPayload -name "Format 4: SHA256(Certs + ASCII)" -secretBytes $secretSHA_ASCII }

Start-Sleep -Seconds 3
$sslStream.Close()
$tcpClient.Close()
