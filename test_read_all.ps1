$ip = "192.168.0.213"
Write-Host "=== Precise Varint Stream Reader (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

function Read-ExactMsg($stream) {
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
}

$callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
$tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
$sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
$sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)

# Build PairingRequest (field 10)
[byte[]]$serviceBytes = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$clientBytes  = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$reqInner = @(10, $serviceBytes.Length) + $serviceBytes + @(18, $clientBytes.Length) + $clientBytes
[byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
[byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter

$sslStream.Write($req, 0, $req.Length)
$sslStream.Flush()
Write-Host "  1. Sent PairingRequest ($($req.Length) bytes)" -ForegroundColor Yellow

$resp1 = Read-ExactMsg $sslStream
if ($resp1) {
    $hex = ($resp1 | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "  Full TV Response to PairingRequest ($($resp1.Length) bytes): $hex" -ForegroundColor Magenta
}

# Build PairingConfiguration (field 30)
[byte[]]$encoding = @(8, 3, 16, 6) # type=3 (hexadecimal), length=6
[byte[]]$inputEnc = @(10, $encoding.Length) + $encoding # field 1 (input_encodings)
[byte[]]$outputEnc = @(18, $encoding.Length) + $encoding # field 2 (output_encodings)
[byte[]]$role = @(24, 1) # field 3 (preferred_role = 1)

[byte[]]$configInner = $inputEnc + $outputEnc + $role
[byte[]]$configOuter = @(8, 2, 16, 200, 1, 242, 1, $configInner.Length) + $configInner
[byte[]]$config = @([byte]$configOuter.Length) + $configOuter

$sslStream.Write($config, 0, $config.Length)
$sslStream.Flush()
Write-Host "  2. Sent PairingConfiguration ($($config.Length) bytes)" -ForegroundColor Yellow

$resp2 = Read-ExactMsg $sslStream
if ($resp2) {
    $hex = ($resp2 | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "  Full TV Response to PairingConfiguration ($($resp2.Length) bytes): $hex" -ForegroundColor Magenta
}

Write-Host "`n>>> CHECK TV SCREEN NOW FOR 6-DIGIT PIN POPUP <<<" -ForegroundColor Cyan
Write-Host "  Keeping socket open for 15 seconds..." -ForegroundColor Gray
Start-Sleep -Seconds 15

$sslStream.Close()
$tcpClient.Close()
Write-Host "  Done." -ForegroundColor Cyan
