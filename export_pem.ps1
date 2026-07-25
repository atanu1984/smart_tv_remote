$pfxPath = 'C:\Code\smart_tv_remote\client_cert.pfx'
$certPemPath = 'C:\Code\smart_tv_remote\client_cert.pem'
$keyPemPath  = 'C:\Code\smart_tv_remote\client_key.pem'

$pfxPwd = ConvertTo-SecureString -String 'temp1234' -Force -AsPlainText
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $pfxPath, $pfxPwd,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)

# Export cert PEM
$certBase64 = [System.Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
$certPem = "-----BEGIN CERTIFICATE-----`n$certBase64`n-----END CERTIFICATE-----"
Set-Content -Path $certPemPath -Value $certPem
Write-Host "Cert PEM written to: $certPemPath"

# Export RSA private key
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
$privKeyBytes = $rsa.ExportRSAPrivateKey()
$keyBase64 = [System.Convert]::ToBase64String($privKeyBytes, 'InsertLineBreaks')
$keyPem = "-----BEGIN RSA PRIVATE KEY-----`n$keyBase64`n-----END RSA PRIVATE KEY-----"
Set-Content -Path $keyPemPath -Value $keyPem
Write-Host "Key PEM written to: $keyPemPath"

Write-Host "Thumbprint: $($cert.Thumbprint)"
Write-Host "Cert first line: $((Get-Content $certPemPath)[0])"
Write-Host "Key first line : $((Get-Content $keyPemPath)[0])"
