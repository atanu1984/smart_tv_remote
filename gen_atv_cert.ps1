Write-Host "=== Generating New Client Certificate with CN=atvremote ===" -ForegroundColor Cyan

# Remove old certificate files
if (Test-Path "C:\Code\smart_tv_remote\client_cert.pfx") { Remove-Item "C:\Code\smart_tv_remote\client_cert.pfx" -Force }
if (Test-Path "C:\Code\smart_tv_remote\client_cert_only.pem") { Remove-Item "C:\Code\smart_tv_remote\client_cert_only.pem" -Force }

# Generate RSA 2048 cert with Subject CN=atvremote
$cert = New-SelfSignedCertificate -Subject "CN=atvremote, O=atvremote" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(10) `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -Type Custom

$pwd = ConvertTo-SecureString -String "temp1234" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "C:\Code\smart_tv_remote\client_cert.pfx" -Password $pwd | Out-Null

# Export PEM format
$certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
$b64 = [Convert]::ToBase64String($certBytes, [Base64FormattingOptions]::InsertLineBreaks)
$pem = "-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----"
Set-Content -Path "C:\Code\smart_tv_remote\client_cert_only.pem" -Value $pem

Write-Host "  Successfully generated client certificate with CN=atvremote!" -ForegroundColor Green
Write-Host "  Saved to client_cert.pfx and client_cert_only.pem" -ForegroundColor Green
