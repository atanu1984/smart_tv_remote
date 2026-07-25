$ip = "192.168.0.213"
Write-Host "=== Exhaustive Secret Hash Solver (${ip}:6467) ===" -ForegroundColor Cyan

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

function Start-PairingSession {
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
    $null = Read-ExactMsg $sslStream

    return @{
        TcpClient  = $tcpClient
        SslStream  = $sslStream
        ServerCert = $serverCert
    }
}

# Start session and trigger PIN popup
$sess = Start-PairingSession

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ">>> 6-CHARACTER PIN POPUP IS NOW DISPLAYED ON YOUR TV SCREEN! <<<" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$pinInput = Read-Host "Type the 6-character PIN code from your TV screen and press ENTER"
$cleanPin = $pinInput.Trim().Replace("-", "").ToUpper()

# Extract RSA Modulus & Exponent
$clientKeys = Get-RsaParamsUnpadded $clientCert
$serverKeys = Get-RsaParamsUnpadded $sess.ServerCert

$sha = [System.Security.Cryptography.SHA256]::Create()

# Candidate Secret Formats:
$pinAscii = [System.Text.Encoding]::UTF8.GetBytes($cleanPin)

[byte[]]$pinHex = New-Object byte[] ($cleanPin.Length / 2)
for ($i = 0; $i -lt $cleanPin.Length; $i += 2) {
    $pinHex[$i / 2] = [Convert]::ToByte($cleanPin.Substring($i, 2), 16)
}

# 1. SHA256(ClientMod + ClientExp + ServerMod + ServerExp + pinHex)
[byte[]]$v1 = $sha.ComputeHash($clientKeys.Modulus + $clientKeys.Exponent + $serverKeys.Modulus + $serverKeys.Exponent + $pinHex)

# 2. SHA256(ClientMod + ClientExp + ServerMod + ServerExp + pinAscii)
[byte[]]$v2 = $sha.ComputeHash($clientKeys.Modulus + $clientKeys.Exponent + $serverKeys.Modulus + $serverKeys.Exponent + $pinAscii)

# 3. SHA256(ClientCertRaw + ServerCertRaw + pinHex)
[byte[]]$v3 = $sha.ComputeHash($clientCert.GetRawCertData() + $sess.ServerCert.GetRawCertData() + $pinHex)

# 4. SHA256(ClientCertRaw + ServerCertRaw + pinAscii)
[byte[]]$v4 = $sha.ComputeHash($clientCert.GetRawCertData() + $sess.ServerCert.GetRawCertData() + $pinAscii)

# 5. Last 4 digits ASCII SHA256
$last4Ascii = [System.Text.Encoding]::UTF8.GetBytes($cleanPin.Substring(2))
[byte[]]$v5 = $sha.ComputeHash($clientKeys.Modulus + $clientKeys.Exponent + $serverKeys.Modulus + $serverKeys.Exponent + $last4Ascii)

# 6. Raw Hex Bytes [0x77, 0x86, 0x55]
[byte[]]$v6 = $pinHex

# 7. Raw ASCII Bytes "778655"
[byte[]]$v7 = $pinAscii

$variants = @(
    @{ Name = "V1: SHA256(ClientKeys + ServerKeys + Hex PIN)"; Data = $v1 },
    @{ Name = "V2: SHA256(ClientKeys + ServerKeys + ASCII PIN)"; Data = $v2 },
    @{ Name = "V3: SHA256(ClientCertRaw + ServerCertRaw + Hex PIN)"; Data = $v3 },
    @{ Name = "V4: SHA256(ClientCertRaw + ServerCertRaw + ASCII PIN)"; Data = $v4 },
    @{ Name = "V5: SHA256(ClientKeys + ServerKeys + Last4 PIN)"; Data = $v5 },
    @{ Name = "V6: Raw Hex Bytes"; Data = $v6 },
    @{ Name = "V7: Raw ASCII Bytes"; Data = $v7 }
)

$currentSess = $sess
foreach ($v in $variants) {
    Write-Host "`nTesting $($v.Name)..." -ForegroundColor Yellow
    [byte[]]$sData = $v.Data
    [byte[]]$sInner = @(10, $sData.Length) + $sData
    [byte[]]$sOuter = @(8, 2, 16, 200, 1, 162, 2, $sInner.Length) + $sInner
    [byte[]]$sMsg = @([byte]$sOuter.Length) + $sOuter

    try {
        $currentSess.SslStream.Write($sMsg, 0, $sMsg.Length)
        $currentSess.SslStream.Flush()

        $resp = Read-ExactMsg $currentSess.SslStream 2500
        if ($resp) {
            $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
            Write-Host "  Response: $hex" -ForegroundColor Magenta
            if ($hex -match "10 C8 01" -or $hex -match "AA 02") {
                Write-Host "`n==========================================================" -ForegroundColor Green
                Write-Host ">>> MATCH FOUND AND PAIRING ACCEPTED BY TV: $($v.Name) <<<" -ForegroundColor Green
                Write-Host "==========================================================" -ForegroundColor Green
                break
            } else {
                Write-Host "  TV Status: Rejected (400)" -ForegroundColor Red
            }
        } else {
            Write-Host "  Timeout" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "  Socket closed by TV. Reconnecting for next variant..." -ForegroundColor DarkYellow
        $currentSess.SslStream.Close()
        $currentSess.TcpClient.Close()
        $currentSess = Start-PairingSession
    }
}

try {
    $currentSess.SslStream.Close()
    $currentSess.TcpClient.Close()
} catch {}
