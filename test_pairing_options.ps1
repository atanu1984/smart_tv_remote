$ip = "192.168.0.213"
Write-Host "=== PairingRequest Option Inspector (${ip}:6467) ===" -ForegroundColor Cyan

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

function Test-Req([string]$label, [byte[]]$reqOuter) {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)

    [byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter
    $sslStream.Write($req, 0, $req.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        Write-Host "  $label -> Response ($($resp.Length) bytes): $hex" -ForegroundColor Yellow
    }

    $sslStream.Close()
    $tcpClient.Close()
}

# 1. Standard PairingRequest (androidtvremote2 + Smart TV Remote)
[byte[]]$s1 = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
[byte[]]$c1 = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
[byte[]]$in1 = @(10, $s1.Length) + $s1 + @(18, $c1.Length) + $c1
Test-Req -label "Req 1: androidtvremote2 + Smart TV Remote" -reqOuter (@(8, 2, 16, 200, 1, 82, $in1.Length) + $in1)

# 2. PairingRequest with atvremote
[byte[]]$s2 = [System.Text.Encoding]::UTF8.GetBytes("atvremote")
[byte[]]$in2 = @(10, $s2.Length) + $s2 + @(18, $c1.Length) + $c1
Test-Req -label "Req 2: atvremote + Smart TV Remote" -reqOuter (@(8, 2, 16, 200, 1, 82, $in2.Length) + $in2)

# 3. PairingRequest with empty service_name
[byte[]]$in3 = @(18, $c1.Length) + $c1
Test-Req -label "Req 3: client_name only" -reqOuter (@(8, 2, 16, 200, 1, 82, $in3.Length) + $in3)
