$ip = "192.168.0.213"
Write-Host "=== Exact Polo Specification Solver (${ip}:6467) ===" -ForegroundColor Cyan

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

function Test-ExactConfig([string]$name, [int]$typeVal, [int]$roleVal) {
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

    # 2. PairingConfiguration: Field 1 (0x0A) -> encoding(type=$typeVal, symbol_length=6), Field 2 (0x10) -> client_role=$roleVal
    [byte[]]$encodingMsg = @(8, $typeVal, 16, 6) # tag 1 (0x08)=typeVal, tag 2 (0x10)=6
    [byte[]]$configInner = @(10, $encodingMsg.Length) + $encodingMsg + @(16, $roleVal) # tag 1 (0x0A)=encoding, tag 2 (0x10)=roleVal
    [byte[]]$configOuter = @(8, 2, 16, 200, 1, 242, 1, $configInner.Length) + $configInner
    [byte[]]$config = @([byte]$configOuter.Length) + $configOuter

    $sslStream.Write($config, 0, $config.Length)
    $sslStream.Flush()

    $resp = Read-ExactMsg $sslStream
    if ($resp) {
        $hex = ($resp | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        if ($hex -notmatch "10 90 03") {
            Write-Host "`n>>> SUCCESS! $name ACCEPTED! Response: $hex <<<" -ForegroundColor Green
            Write-Host "`n>>> CHECK TV SCREEN NOW FOR 6-DIGIT PIN POPUP <<<" -ForegroundColor Cyan
            Start-Sleep -Seconds 15
        } else {
            Write-Host "  REJECTED (400) -> $name" -ForegroundColor Red
        }
    } else {
        Write-Host "  TIMEOUT -> $name" -ForegroundColor DarkYellow
    }

    $sslStream.Close()
    $tcpClient.Close()
}

# Test matrix:
Test-ExactConfig -name "Type=1 (ALPHANUMERIC), Role=1 (INPUT)"  -typeVal 1 -roleVal 1
Test-ExactConfig -name "Type=2 (NUMERIC), Role=1 (INPUT)"       -typeVal 2 -roleVal 1
Test-ExactConfig -name "Type=3 (HEXADECIMAL), Role=1 (INPUT)"   -typeVal 3 -roleVal 1
Test-ExactConfig -name "Type=1 (ALPHANUMERIC), Role=2 (OUTPUT)" -typeVal 1 -roleVal 2
Test-ExactConfig -name "Type=2 (NUMERIC), Role=2 (OUTPUT)"      -typeVal 2 -roleVal 2
Test-ExactConfig -name "Type=3 (HEXADECIMAL), Role=2 (OUTPUT)"  -typeVal 3 -roleVal 2
