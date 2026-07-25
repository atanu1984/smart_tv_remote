$ip = "192.168.0.213"
Write-Host "=== Generating Self-Signed Client Cert & Testing mTLS ===" -ForegroundColor Cyan

# Generate a self-signed cert in PowerShell
$cert = New-SelfSignedCertificate `
    -Subject "CN=SmartTVRemote,O=SmartTVRemoteApp" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -KeyExportPolicy Exportable `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -NotAfter (Get-Date).AddYears(10) `
    -CertStoreLocation "Cert:\CurrentUser\My"

Write-Host "  Generated cert: $($cert.Thumbprint)" -ForegroundColor Green

# Export to PFX (PKCS12) temporarily
$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$pemPath = "C:\Code\smart_tv_remote\client_cert.pem"
$keyPath = "C:\Code\smart_tv_remote\client_key.pem"
$pwd = ConvertTo-SecureString -String "temp1234" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pwd | Out-Null
Write-Host "  Exported to PFX: $pfxPath" -ForegroundColor Green

# Now test connecting with this client cert to TV port 6467
Write-Host "`n--- Testing mTLS with client cert on port 6467 ---" -ForegroundColor Yellow
try {
    $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    $certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)

    $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ip, 6467)
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
    $sslStream.AuthenticateAsClient($ip, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
    Write-Host "  mTLS HANDSHAKE SUCCESS on port 6467!" -ForegroundColor Green
    Write-Host "  Cipher: $($sslStream.CipherAlgorithm)" -ForegroundColor Yellow

    $buf = New-Object byte[] 256
    $sslStream.ReadTimeout = 3000
    try {
        $n = $sslStream.Read($buf, 0, 256)
        Write-Host "  TV Response ($n bytes): $([BitConverter]::ToString($buf[0..([Math]::Min($n-1,15))]))" -ForegroundColor Magenta
    } catch { Write-Host "  No data (or TV is waiting for our PairingRequest)" -ForegroundColor DarkYellow }
    $sslStream.Close()
    $tcpClient.Close()
} catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) { Write-Host "  Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
}

# Show cert fingerprint for embedding
Write-Host "`n=== Cert Details ===" -ForegroundColor Cyan
Write-Host "  Thumbprint : $($cert.Thumbprint)" -ForegroundColor Yellow
Write-Host "  Subject    : $($cert.Subject)" -ForegroundColor Yellow
Write-Host "  Not After  : $($cert.NotAfter)" -ForegroundColor Yellow

# Export PEM (cert + key) using openssl if available, otherwise note the PFX path
Write-Host "`nPFX file: $pfxPath (password: temp1234)" -ForegroundColor Cyan
Write-Host "This PFX can be converted to PEM using: openssl pkcs12 -in client_cert.pfx -out client.pem -nodes -passin pass:temp1234" -ForegroundColor Gray
