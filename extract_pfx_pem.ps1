$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

# Export cert PEM
$certBase64 = [Convert]::ToBase64String($cert.RawData, [System.Base64FormattingOptions]::InsertLineBreaks)
$certPem = "-----BEGIN CERTIFICATE-----`r`n" + $certBase64 + "`r`n-----END CERTIFICATE-----"

# Export private key using RSACryptoServiceProvider or RSACng export approach
$rsaKey = $cert.PrivateKey
if ($rsaKey -ne $null) {
    # Try CSP export (works for RSACryptoServiceProvider)
    try {
        $rsaCSP = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsaCSP.ImportParameters($rsaKey.ExportParameters($true))
        $pkcs8 = $rsaCSP.ExportEncryptedPkcs8PrivateKey(
            [System.ReadOnlySpan[char]]::Empty, 
            (New-Object System.Security.Cryptography.PbeParameters(
                [System.Security.Cryptography.PbeEncryptionAlgorithm]::Aes256Cbc,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                100000
            ))
        )
        Write-Host "CSP export worked"
    } catch {
        Write-Host "CSP export failed: $_"
    }
    
    # Try getting RSA params directly
    try {
        $params = $rsaKey.ExportParameters($true)
        $modHex = ($params.Modulus | ForEach-Object { "{0:X2}" -f $_ }) -join ""
        Write-Host "RSA Modulus (hex): $modHex"
        Write-Host "Modulus length: $($params.Modulus.Length) bytes"
    } catch {
        Write-Host "ExportParameters failed: $_"
    }
} else {
    Write-Host "PrivateKey is null, trying GetRSAPrivateKey..."
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    
    # Export using PbeParameters
    try {
        $pbeParams = New-Object System.Security.Cryptography.PbeParameters(
            [System.Security.Cryptography.PbeEncryptionAlgorithm]::Aes256Cbc,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            1
        )
        $encBytes = $rsa.ExportEncryptedPkcs8PrivateKey("", $pbeParams)
        Write-Host "Encrypted export succeeded"
    } catch {
        Write-Host "EncryptedPkcs8 failed: $_"
    }
    
    # Try RSA params
    try {
        $params = $rsa.ExportParameters($true)
        $modHex = ($params.Modulus | ForEach-Object { "{0:X2}" -f $_ }) -join ""
        Write-Host "RSA Modulus (hex, first 32 bytes): " + $modHex.Substring(0, 64)
        Write-Host "Modulus length: $($params.Modulus.Length) bytes"
        
        # Build PKCS#1 RSAPrivateKey manually
        # Write the modulus, exponent, etc to construct PKCS8
        Write-Host "D (private exponent) length: $($params.D.Length) bytes"
    } catch {
        Write-Host "ExportParameters failed: $_"
    }
}

Write-Host "=== CERT PEM ===" -ForegroundColor Cyan
Write-Host $certPem

# Try openssl if available
try {
    $opensslResult = & openssl pkcs12 -in $pfxPath -nocerts -nodes -passin pass:temp1234 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "=== KEY PEM (openssl) ===" -ForegroundColor Cyan
        Write-Host $opensslResult
    }
} catch {
    Write-Host "openssl not available"
}
