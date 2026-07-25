param(
    [int]$variantChoice = 0
)

$ip = "192.168.0.213"
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "=== GOOGLE TV POLO ALL HASH SOLVER ===" -ForegroundColor Cyan
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

# 1. Initiate fresh mTLS session cleanly
Write-Host "`n[1] Connecting to TV at ${ip}:6467..." -ForegroundColor Yellow
$tcpClient = $null
$sslStream = $null

try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $ar = $tcpClient.BeginConnect($ip, 6467, $null, $null)
    if (-not $ar.AsyncWaitHandle.WaitOne(4000, $false)) {
        $tcpClient.Close()
        throw "TCP Connection to ${ip}:6467 timed out. Please wait 5 seconds and try again."
    }
    $tcpClient.EndConnect($ar)

    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
    $serverCert = $sslStream.RemoteCertificate
    Write-Host "  mTLS Handshake Connected!" -ForegroundColor Green
} catch {
    Write-Host "`n[CONNECTION ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($tcpClient) { $tcpClient.Close() }
    exit
}

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

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ">>> CHECK YOUR TV SCREEN NOW FOR THE 6-CHARACTER PIN! <<<" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$pinInput = Read-Host "Type the 6-character PIN code currently on your TV screen and press ENTER"
$cleanPin = $pinInput.Trim().Replace("-", "").ToUpper()

[byte[]]$pinAscii = [System.Text.Encoding]::UTF8.GetBytes($cleanPin)
[byte[]]$pinHex = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $pinHex[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

$sha = [System.Security.Cryptography.SHA256]::Create()

# Extract Java PublicKey.getEncoded() bytes (SubjectPublicKeyInfo DER)
[byte[]]$clientPubKeyDer = $clientCert.GetPublicKey()
[byte[]]$serverPubKeyDer = $serverCert.GetPublicKey()

# Candidate Secret Formulas
$candidates = @(
    @{ Name = "3: SHA256(ServerPubKeyDER + ClientPubKeyDER + Hex PIN)"; Secret = $sha.ComputeHash($serverPubKeyDer + $clientPubKeyDer + $pinHex) },
    @{ Name = "4: SHA256(ServerPubKeyDER + ClientPubKeyDER + ASCII PIN)"; Secret = $sha.ComputeHash($serverPubKeyDer + $clientPubKeyDer + $pinAscii) },
    @{ Name = "5: SHA256(Hex PIN [0x30, 0xA1, 0x50])"; Secret = $sha.ComputeHash($pinHex) },
    @{ Name = "6: SHA256(ASCII PIN '30A150')"; Secret = $sha.ComputeHash($pinAscii) },
    @{ Name = "7: SHA256(ClientCertRaw + PIN_Hex)"; Secret = $sha.ComputeHash($clientCert.RawData + $pinHex) },
    @{ Name = "8: SHA256(ServerCertRaw + PIN_Hex)"; Secret = $sha.ComputeHash($serverCert.RawData + $pinHex) }
)

if ($variantChoice -lt 3 -or $variantChoice -gt 8) {
    Write-Host "`nSelect Secret Variant to Test for PIN '$cleanPin':" -ForegroundColor Yellow
    for ($i = 0; $i -lt $candidates.Length; $i++) {
        Write-Host "  [$($i+3)] $($candidates[$i].Name)" -ForegroundColor White
    }
    $choiceStr = Read-Host "`nEnter option number (3-8)"
    [int]::TryParse($choiceStr, [ref]$variantChoice) | Out-Null
}

if ($variantChoice -lt 3 -or $variantChoice -gt 8) { $variantChoice = 3 }
$selected = $candidates[$variantChoice - 3]

Write-Host "`nTesting $($selected.Name) ($($selected.Secret.Length) bytes)..." -ForegroundColor Yellow

[byte[]]$secretInner = @(10, $selected.Secret.Length) + $selected.Secret
[byte[]]$secretOuter = @(8, 2, 16, 200, 1, 194, 2, $secretInner.Length) + $secretInner
[byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter

$sslStream.Write($secretMsg, 0, $secretMsg.Length)
$sslStream.Flush()

$resp = Read-ExactMsg $sslStream 4000
$resultText = Decode-ProtobufStatus $resp
Write-Host "TV Response Result: $resultText" -ForegroundColor $(if ($resultText -match "200") { "Green" } else { "Red" })

$sslStream.Close()
$tcpClient.Close()
Write-Host "`nDone." -ForegroundColor Cyan
