$pfxPath = 'C:\Code\smart_tv_remote\client_cert.pfx'
$keyPemPath = 'C:\Code\smart_tv_remote\client_key.pem'
$pfxPwd = ConvertTo-SecureString -String 'temp1234' -Force -AsPlainText

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $pfxPath, $pfxPwd,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)

# Use RSACng ExportParameters then manually encode as PKCS#1
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
$params = $rsa.ExportParameters($true)

# Export as PKCS8 PrivateKeyInfo (RSA)
$privKeyBytes = $rsa.ExportPkcs8PrivateKey()
$keyBase64 = [System.Convert]::ToBase64String($privKeyBytes, 'InsertLineBreaks')
$keyPem = "-----BEGIN PRIVATE KEY-----`n$keyBase64`n-----END PRIVATE KEY-----"
Set-Content -Path $keyPemPath -Value $keyPem
Write-Host "Key PEM (PKCS8) written to: $keyPemPath"
Write-Host "Key first line: $((Get-Content $keyPemPath)[0])"
Write-Host "Done."
