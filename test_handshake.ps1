$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

# Discover target TV on local network or test known IP
$subnet = "192.168.0"
Write-Host "Scanning subnet $subnet for port 6467..." -ForegroundColor Cyan

$targetIp = $null

foreach ($i in 1..254) {
    $ip = "$subnet.$i"
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar = $tcp.BeginConnect($ip, 6467, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(50, $false)) {
            $tcp.EndConnect($ar)
            Write-Host "Found open port 6467 at $ip!" -ForegroundColor Green
            $targetIp = $ip
            $tcp.Close()
            break
        }
        $tcp.Close()
    } catch {}
}

if (-not $targetIp) {
    $targetIp = "192.168.0.213"
}

Write-Host "Testing mTLS Handshake on $targetIp:6467..." -ForegroundColor Cyan
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($targetIp, 6467)
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($targetIp, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
    
    Write-Host "SUCCESS: mTLS Handshake completed with $targetIp:6467!" -ForegroundColor Green
    Write-Host "Server Cert Subject: $($sslStream.RemoteCertificate.Subject)" -ForegroundColor Yellow
    Write-Host "Server Cert Issuer: $($sslStream.RemoteCertificate.Issuer)" -ForegroundColor Yellow
    
    $sslStream.Close()
    $tcpClient.Close()
} catch {
    Write-Host "HANDSHAKE FAILED on $targetIp:6467 -> $($_.Exception.Message)" -ForegroundColor Red
}
