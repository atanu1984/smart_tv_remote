$ip = "192.168.0.213"
Write-Host "=== Live PIN Verification & Secret Formula Solver (${ip}:6467) ===" -ForegroundColor Cyan

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

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ">>> 6-DIGIT PIN POPUP IS NOW DISPLAYED ON YOUR TV SCREEN! <<<" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$pin = Read-Host "Enter the 6-digit PIN code currently showing on your TV screen"
$cleanPin = $pin.Trim().Replace("-", "").ToUpper()

# Candidate A: Plain ASCII bytes
[byte[]]$secretA = [System.Text.Encoding]::UTF8.GetBytes($cleanPin)

# Candidate B: Raw 3 Hex Bytes
[byte[]]$secretB = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $secretB[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

# Candidate C: SHA256(ClientCertRaw + ServerCertRaw + PlainBytes)
$sha = [System.Security.Cryptography.SHA256]::Create()
[byte[]]$clientRaw = $clientCert.GetRawCertData()
[byte[]]$serverRaw = $serverCert.GetRawCertData()
[byte[]]$concatC  = $clientRaw + $serverRaw + $secretA
[byte[]]$secretC  = $sha.ComputeHash($concatC)

# Candidate D: SHA256(ClientCertRaw + ServerCertRaw + HexBytes)
[byte[]]$concatD  = $clientRaw + $serverRaw + $secretB
[byte[]]$secretD  = $sha.ComputeHash($concatD)

function Test-SecretPayload([string]$label, [byte[]]$secretBytes) {
    Write-Host "`nSending $label ($($secretBytes.Length) bytes)..." -ForegroundColor Yellow
    [byte[]]$secretInner = @(10, $secretBytes.Length) + $secretBytes
    [byte[]]$secretOuter = @(8, 2, 16, 200, 1, 162, 2, $secretInner.Length) + $secretInner
    [byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter

    $sslStream.Write($secretMsg, 0, $secretMsg.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream 2000
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        Write-Host "  Response ($($resp.Length) bytes): $hex" -ForegroundColor Magenta
        if ($hex -match "10 C8 01" -or $hex -match "AA 02") {
            Write-Host "`n==========================================================" -ForegroundColor Green
            Write-Host ">>> MATCH SUCCESSFUL! $label STORED CERT ON TV! <<<" -ForegroundColor Green
            Write-Host "==========================================================" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  REJECTED BY TV" -ForegroundColor Red
        }
    } else {
        Write-Host "  No response / Timeout" -ForegroundColor DarkYellow
    }
    return $false
}

$success = Test-SecretPayload -label "Candidate A (ASCII Bytes)" -secretBytes $secretA
if (-not $success) { $success = Test-SecretPayload -label "Candidate B (Raw Hex Bytes)" -secretBytes $secretB }
if (-not $success) { $success = Test-SecretPayload -label "Candidate C (SHA256 Certs + ASCII)" -secretBytes $secretC }
if (-not $success) { $success = Test-SecretPayload -label "Candidate D (SHA256 Certs + Hex)" -secretBytes $secretD }

Start-Sleep -Seconds 5
$sslStream.Close()
$tcpClient.Close()
