Write-Host "Generating new matched RSA 2048-bit cert using CNG export..." -ForegroundColor Cyan

# Generate cert in store with exportable key
$cert = New-SelfSignedCertificate `
    -Subject "CN=atvrremote, O=atvrremote" `
    -KeyAlgorithm RSA -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(10)

Write-Host "Cert created: $($cert.Thumbprint)" -ForegroundColor Green

# Export cert PEM
$certBase64 = [Convert]::ToBase64String($cert.RawData, [System.Base64FormattingOptions]::InsertLineBreaks)
$certPem = "-----BEGIN CERTIFICATE-----`r`n" + $certBase64 + "`r`n-----END CERTIFICATE-----"

# Export PRIVATE KEY using CNG Pkcs8PrivateBlob
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
$keyBlob = $rsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
$keyBase64 = [Convert]::ToBase64String($keyBlob, [System.Base64FormattingOptions]::InsertLineBreaks)
$keyPem = "-----BEGIN PRIVATE KEY-----`r`n" + $keyBase64 + "`r`n-----END PRIVATE KEY-----"

# Save PFX for debug script
$pwd = ConvertTo-SecureString "temp1234" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath "C:\Code\smart_tv_remote\app_client_cert.pfx" -Password $pwd | Out-Null
Write-Host "Exported C:\Code\smart_tv_remote\app_client_cert.pfx" -ForegroundColor Green

# Save to files
$certPem | Out-File -FilePath "C:\Code\smart_tv_remote\new_client_cert.pem" -Encoding ASCII
$keyPem | Out-File -FilePath "C:\Code\smart_tv_remote\new_client_key.pem" -Encoding ASCII

# Clean up store
Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue
Write-Host "`nSaved to app_client_cert.pfx, new_client_cert.pem and new_client_key.pem" -ForegroundColor Green
