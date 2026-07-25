$ip = "192.168.0.213"
Write-Host "=== Testing All PairingConfiguration Variations (${ip}:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

function Send-ConfigTest {
    param(
        [string]$name,
        [byte[]]$configInner
    )
    
    Write-Host "`n--- Testing Payload: $name ---" -ForegroundColor Yellow
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
    
    [byte[]]$buf = New-Object byte[] 512
    $sslStream.ReadTimeout = 1500
    try { $null = $sslStream.Read($buf, 0, 512) } catch {}

    # 2. Send PairingConfiguration
    [byte[]]$configOuter = @(8, 2, 16, 200, 1, 242, 1, $configInner.Length) + $configInner
    [byte[]]$config = @([byte]$configOuter.Length) + $configOuter

    $sslStream.Write($config, 0, $config.Length)
    $sslStream.Flush()
    Write-Host "  Sent Config Hex: $([BitConverter]::ToString($config))" -ForegroundColor Gray

    try {
        $n = $sslStream.Read($buf, 0, 512)
        $hex = ($buf[0..($n-1)] | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        Write-Host "  TV Response ($n bytes): $hex" -ForegroundColor Green
    } catch {
        Write-Host "  TV Response: Timeout / No Response" -ForegroundColor Red
    }

    Start-Sleep -Seconds 3
    $sslStream.Close()
    $tcpClient.Close()
}

# Var 1: Single encoding (type=1 ALPHANUMERIC, len=6), role=1
# Inner: field 1 (0x0A) -> encoding (8,1,16,6), field 2 (0x10) -> role=1
Send-ConfigTest -name "Var 1: Alphanumeric (type=1, len=6, role=1)" -configInner @(10, 4, 8, 1, 16, 6, 16, 1)

# Var 2: Single encoding (type=2 NUMERIC, len=6), role=1
Send-ConfigTest -name "Var 2: Numeric (type=2, len=6, role=1)" -configInner @(10, 4, 8, 2, 16, 6, 16, 1)

# Var 3: Single encoding (type=3 HEXADECIMAL, len=6), role=1
Send-ConfigTest -name "Var 3: Hexadecimal (type=3, len=6, role=1)" -configInner @(10, 4, 8, 3, 16, 6, 16, 1)

# Var 4: Field 1 role=1, Field 2 encoding (type=2, len=6), Field 3 symbol=6
Send-ConfigTest -name "Var 4: Legacy Polo (role=1, type=2, len=6)" -configInner @(8, 1, 18, 4, 8, 2, 16, 6)

Write-Host "`nDone probing all variations." -ForegroundColor Cyan
