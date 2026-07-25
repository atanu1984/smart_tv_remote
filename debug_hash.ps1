$ip = "192.168.0.213"
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "=== RSA KEY DEBUG - EXACT BYTES GOING INTO HASH ===" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\app_client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
$clientCert = $certCollection[0]

function Format-Hex([byte[]]$bytes) {
    return ($bytes | ForEach-Object { "{0:X2}" -f $_ }) -join " "
}

function Read-ExactMsg($stream, [int]$timeoutMs = 3500) {
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
    } catch { return $null }
}

# Connect mTLS to get server cert
$tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
$callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
$sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
$sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
$serverCertRaw = $sslStream.RemoteCertificate
# Wrap as X509Certificate2 for RSA access
$serverCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($serverCertRaw)
Write-Host "  mTLS Connected!" -ForegroundColor Green

# Step 1: PairingRequest
[byte[]]$s = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$c = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$reqInner = @(10, $s.Length) + $s + @(18, $c.Length) + $c
[byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
[byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter
$sslStream.Write($req, 0, $req.Length); $sslStream.Flush()
$r1 = Read-ExactMsg $sslStream; Write-Host "Step1 response: $(Format-Hex $r1)" -ForegroundColor DarkGray

# Step 2: PairingOption
[byte[]]$encodingMsg = @(8, 3, 16, 6)
[byte[]]$optInner = @(10, $encodingMsg.Length) + $encodingMsg + @(18, $encodingMsg.Length) + $encodingMsg + @(24, 1)
[byte[]]$optOuter = @(8, 2, 16, 200, 1, 162, 1, $optInner.Length) + $optInner
[byte[]]$opt = @([byte]$optOuter.Length) + $optOuter
$sslStream.Write($opt, 0, $opt.Length); $sslStream.Flush()
$r2 = Read-ExactMsg $sslStream; Write-Host "Step2 response: $(Format-Hex $r2)" -ForegroundColor DarkGray

# Step 3: PairingConfiguration
[byte[]]$cfgInner = @(10, $encodingMsg.Length) + $encodingMsg + @(16, 1)
[byte[]]$cfgOuter = @(8, 2, 16, 200, 1, 242, 1, $cfgInner.Length) + $cfgInner
[byte[]]$cfg = @([byte]$cfgOuter.Length) + $cfgOuter
$sslStream.Write($cfg, 0, $cfg.Length); $sslStream.Flush()
$r3 = Read-ExactMsg $sslStream; Write-Host "Step3 response: $(Format-Hex $r3)" -ForegroundColor DarkGray

$pinInput = Read-Host "`nEnter PIN from TV"
$cleanPin = $pinInput.Trim().ToUpper()

# Extract RSA params via .NET (NO leading zero stripping)
$clientRsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($clientCert)
$serverRsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($serverCert)
$cParams = $clientRsa.ExportParameters($false)
$sParams = $serverRsa.ExportParameters($false)

[byte[]]$cMod = $cParams.Modulus   # RAW from .NET, no stripping
[byte[]]$cExp = $cParams.Exponent
[byte[]]$sMod = $sParams.Modulus
[byte[]]$sExp = $sParams.Exponent

Write-Host "`n--- CLIENT RSA ---" -ForegroundColor Yellow
Write-Host "Modulus ($($cMod.Length) bytes): $(Format-Hex $cMod[0..7])..." -ForegroundColor White
Write-Host "Exponent ($($cExp.Length) bytes): $(Format-Hex $cExp)" -ForegroundColor White

Write-Host "`n--- SERVER RSA ---" -ForegroundColor Yellow
Write-Host "Modulus ($($sMod.Length) bytes): $(Format-Hex $sMod[0..7])..." -ForegroundColor White
Write-Host "Exponent ($($sExp.Length) bytes): $(Format-Hex $sExp)" -ForegroundColor White

# Louis49: exponent is "0x10001" -> exponent.slice(2) = "10001" -> "0" + "10001" = "010001"
# That means exponent bytes = [0x01, 0x00, 0x01]  <-- 3 bytes
[byte[]]$cExp3 = @(0x01, 0x00, 0x01)  # 65537 as 3 bytes, no leading zero
[byte[]]$sExp3 = @(0x01, 0x00, 0x01)
Write-Host "`nLouis49 Exponent (3 bytes always): $(Format-Hex $cExp3)" -ForegroundColor Cyan

# Louis49: code.slice(2) on "9BC21E" = "C21E" (drops first 2 chars)
$pinSliced = $cleanPin.Substring(2)
[byte[]]$pinHexSliced = New-Object byte[] ($pinSliced.Length / 2)
for ($i = 0; $i -lt $pinSliced.Length; $i += 2) {
    $pinHexSliced[$i / 2] = [Convert]::ToByte($pinSliced.Substring($i, 2), 16)
}
Write-Host "`n--- PIN ---" -ForegroundColor Yellow
Write-Host "Raw PIN: '$cleanPin'" -ForegroundColor White
Write-Host "Sliced PIN (code.slice(2)): '$pinSliced'" -ForegroundColor White
Write-Host "Sliced PIN bytes ($(($pinHexSliced.Length)) bytes): $(Format-Hex $pinHexSliced)" -ForegroundColor White

$sha = [System.Security.Cryptography.SHA256]::Create()

# THE EXACT LOUIS49 FORMULA:
# SHA256(cMod + cExp3 + sMod + sExp3 + pinHexSliced)
Write-Host "`n--- COMPUTING EXACT LOUIS49 HASH ---" -ForegroundColor Yellow
Write-Host "  Data = ClientMod($($cMod.Length)B) + ClientExp($($cExp3.Length)B) + ServerMod($($sMod.Length)B) + ServerExp($($sExp3.Length)B) + PinSliced($($pinHexSliced.Length)B)" -ForegroundColor White

$hashData = $cMod + $cExp3 + $sMod + $sExp3 + $pinHexSliced
[byte[]]$hash = $sha.ComputeHash($hashData)
Write-Host "  Hash ($($hash.Length) bytes): $(Format-Hex $hash)" -ForegroundColor Cyan

[byte[]]$secretInner = @(10, $hash.Length) + $hash
[byte[]]$secretOuter = @(8, 2, 16, 200, 1, 194, 2, $secretInner.Length) + $secretInner
[byte[]]$secretMsg = @([byte]$secretOuter.Length) + $secretOuter
Write-Host "  PairingSecret message ($(($secretMsg.Length)) bytes): $(Format-Hex $secretMsg)" -ForegroundColor DarkGray

$sslStream.Write($secretMsg, 0, $secretMsg.Length); $sslStream.Flush()
$resp = Read-ExactMsg $sslStream 4000
if ($resp) { Write-Host "`nTV RAW Response: $(Format-Hex $resp)" -ForegroundColor Magenta }
else { Write-Host "`nTV Response: NO RESPONSE / Connection Closed" -ForegroundColor Red }

$sslStream.Close(); $tcpClient.Close()
Write-Host "`nDone." -ForegroundColor Cyan
