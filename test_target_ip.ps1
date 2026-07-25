param(
    [string]$targetIp = "192.168.0.52"
)

Write-Host "=== Direct mTLS Handshake Test ($targetIp:6467) ===" -ForegroundColor Cyan

$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $ar = $tcp.BeginConnect($targetIp, 6467, $null, $null)
    if (-not $ar.AsyncWaitHandle.WaitOne(3000, $false)) {
        $tcp.Close()
        throw "TCP Connection Timeout to ${targetIp}:6467"
    }
    $tcp.EndConnect($ar)
    Write-Host "1. TCP Connection to ${targetIp}:6467 established!" -ForegroundColor Green

    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $sslStream = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $callback)
    $sslStream.ReadTimeout = 5000
    $sslStream.WriteTimeout = 5000
    
    $sslStream.AuthenticateAsClient($targetIp, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
    Write-Host "2. SUCCESS: mTLS Handshake completed cleanly!" -ForegroundColor Green
    Write-Host "   Server Subject: $($sslStream.RemoteCertificate.Subject)" -ForegroundColor Yellow
    Write-Host "   Server Issuer:  $($sslStream.RemoteCertificate.Issuer)" -ForegroundColor Yellow
    
    $sslStream.Close()
    $tcp.Close()
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
