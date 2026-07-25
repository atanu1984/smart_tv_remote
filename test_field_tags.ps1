$ip = "192.168.0.213"
Write-Host "=== Field Tag Discovery Scanner (${ip}:6467) ===" -ForegroundColor Cyan

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

function Encode-Varint([uint32]$val) {
    $bytes = New-Object System.Collections.Generic.List[byte]
    while ($val -ge 0x80) {
        $bytes.Add([byte](($val -band 0x7F) -bor 0x80))
        $val = $val -shr 7
    }
    $bytes.Add([byte]$val)
    return $bytes.ToArray()
}

function Test-FieldTag([int]$fieldNum) {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)

    # 1. PairingRequest
    [byte[]]$s = [System.Text.Encoding]::UTF8.GetBytes("androidtvremote2")
    [byte[]]$c = [System.Text.Encoding]::UTF8.GetBytes("Smart TV Remote")
    [byte[]]$reqInner = @(10, $s.Length) + $s + @(18, $c.Length) + $c
    [byte[]]$reqOuter = @(8, 2, 16, 200, 1, 82, $reqInner.Length) + $reqInner
    [byte[]]$req = @([byte]$reqOuter.Length) + $reqOuter

    $sslStream.Write($req, 0, $req.Length)
    $sslStream.Flush()
    $null = Read-ExactMsg $sslStream

    # 2. Build PairingConfiguration using target fieldNum
    [byte[]]$encodingMsg = @(8, 2, 16, 6) # type=2 NUMERIC, len=6
    [byte[]]$configInner = @(10, $encodingMsg.Length) + $encodingMsg + @(16, 1) # encoding + role=1
    
    [uint32]$tagVal = ($fieldNum -shl 3) -bor 2 # wire type 2
    [byte[]]$tagBytes = Encode-Varint $tagVal
    
    [byte[]]$subMsg = $tagBytes + @([byte]$configInner.Length) + $configInner
    [byte[]]$configOuter = @(8, 2, 16, 200, 1) + $subMsg
    [byte[]]$config = @([byte]$configOuter.Length) + $configOuter

    $sslStream.Write($config, 0, $config.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        if ($hex -notmatch "10 90 03") {
            Write-Host "`n>>> MATCH FOUND! Field Tag $fieldNum returned: $hex <<<" -ForegroundColor Green
            Write-Host "`n>>> CHECK TV SCREEN NOW FOR 6-DIGIT PIN POPUP <<<" -ForegroundColor Cyan
            Start-Sleep -Seconds 15
        } else {
            Write-Host "  Field $fieldNum -> 400 Error" -ForegroundColor Red
        }
    } else {
        Write-Host "  Field $fieldNum -> Timeout" -ForegroundColor DarkYellow
    }

    $sslStream.Close()
    $tcpClient.Close()
}

$tagsToScan = @(1, 2, 3, 4, 5, 10, 11, 12, 20, 21, 30, 31, 40, 41, 50, 100)
foreach ($t in $tagsToScan) {
    Test-FieldTag $t
}
