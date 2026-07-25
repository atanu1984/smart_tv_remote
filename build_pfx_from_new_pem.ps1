$certPem = Get-Content "C:\Code\smart_tv_remote\new_client_cert.pem" -Raw
$keyPem = Get-Content "C:\Code\smart_tv_remote\new_client_key.pem" -Raw

$certBytes = [Convert]::FromBase64String(($certPem -replace '-----[A-Z ]+-----', '' -replace '\s', ''))
$keyBytes = [Convert]::FromBase64String(($keyPem -replace '-----[A-Z ]+-----', '' -replace '\s', ''))

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certBytes)

Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

public class PfxBuilder {
    public static void SavePfx(byte[] certDer, byte[] pkcs8Key, string pfxPath, string password) {
        using (var rsa = RSA.Create()) {
            rsa.ImportPkcs8PrivateKey(pkcs8Key, out _);
            using (var cert = new X509Certificate2(certDer))
            using (var certWithKey = cert.CopyWithPrivateKey(rsa)) {
                byte[] pfxBytes = certWithKey.Export(X509ContentType.Pfx, password);
                System.IO.File.WriteAllBytes(pfxPath, pfxBytes);
            }
        }
    }
}
'@

[PfxBuilder]::SavePfx($certBytes, $keyBytes, "C:\Code\smart_tv_remote\app_client_cert.pfx", "temp1234")
Write-Host "Created app_client_cert.pfx successfully!" -ForegroundColor Green
