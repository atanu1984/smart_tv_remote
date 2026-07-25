$pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
$clientCert = $certCollection[0]

$clientPublicKeyBytes = $clientCert.GetPublicKey()
Write-Host "Client SubjectPublicKeyInfo length: $($clientPublicKeyBytes.Length) bytes" -ForegroundColor Cyan
Write-Host "Client SubjectPublicKeyInfo Hex (first 32 bytes): $(($clientPublicKeyBytes[0..31] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')" -ForegroundColor Yellow
