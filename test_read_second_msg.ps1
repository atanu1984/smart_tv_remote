$ip = "192.168.0.213"
Write-Host "=== Listening for TV PairingOption (Message 2) (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

function Read-ExactMsg($stream, [int]$timeoutMs = 2000) {
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

# 1. Send PairingRequest
[byte[]]$serviceBytes = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$clientBytes  = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$reqInner = @(10, $serviceBytes.Length) + $serviceBytes + @(18, $clientBytes.Length) + $clientBytes
[byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
[byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter

$sslStream.Write($req, 0, $req.Length)
$sslStream.Flush()
Write-Host "  Sent PairingRequest ($($req.Length) bytes)" -ForegroundColor Yellow

$msg1 = Read-ExactMsg $sslStream 2000
if ($msg1) {
    $hex1 = ($msg1 | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "  Received Msg 1 from TV ($($msg1.Length) bytes): $hex1" -ForegroundColor Magenta
}

$msg2 = Read-ExactMsg $sslStream 3000
if ($msg2) {
    $hex2 = ($msg2 | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "  Received Msg 2 (PairingOption!) from TV ($($msg2.Length) bytes): $hex2" -ForegroundColor Green
} else {
    Write-Host "  Msg 2 Timeout / No Msg 2 sent by TV" -ForegroundColor DarkYellow
}

$sslStream.Close()
$tcpClient.Close()
