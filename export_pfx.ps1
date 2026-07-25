$pfxPath = 'C:\Code\smart_tv_remote\client_cert.pfx'
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, 'temp1234', [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

# Convert RawData to Cert PEM
$certBase64 = [Convert]::ToBase64String($cert.RawData, [System.Base64FormattingOptions]::InsertLineBreaks)
$certPem = "-----BEGIN CERTIFICATE-----`r`n" + $certBase64 + "`r`n-----END CERTIFICATE-----"

$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)

if ($rsa -is [System.Security.Cryptography.RSACng]) {
    $keyBytes = $rsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
    $keyBase64 = [Convert]::ToBase64String($keyBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
    $keyPem = "-----BEGIN PRIVATE KEY-----`r`n" + $keyBase64 + "`r`n-----END PRIVATE KEY-----"
} else {
    $params = $rsa.ExportParameters($true)
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Security.Cryptography;

public class Pkcs8Exporter {
    public static string ExportPkcs8(RSAParameters p) {
        using (var stream = new MemoryStream()) {
            byte[] pkcs1 = BuildPkcs1(p);
            byte[] pkcs8 = BuildPkcs8Wrapper(pkcs1);
            return "-----BEGIN PRIVATE KEY-----\r\n" + Convert.ToBase64String(pkcs8, Base64FormattingOptions.InsertLineBreaks) + "\r\n-----END PRIVATE KEY-----";
        }
    }

    private static byte[] BuildPkcs1(RSAParameters p) {
        using (var ms = new MemoryStream()) {
            WriteInt(ms, new byte[] { 0 });
            WriteInt(ms, p.Modulus);
            WriteInt(ms, p.Exponent);
            WriteInt(ms, p.D);
            WriteInt(ms, p.P);
            WriteInt(ms, p.Q);
            WriteInt(ms, p.DP);
            WriteInt(ms, p.DQ);
            WriteInt(ms, p.InverseQ);
            return WrapSeq(ms.ToArray());
        }
    }

    private static byte[] BuildPkcs8Wrapper(byte[] pkcs1) {
        using (var ms = new MemoryStream()) {
            WriteInt(ms, new byte[] { 0 });
            byte[] algId = new byte[] { 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00 };
            ms.Write(algId, 0, algId.Length);
            WriteLen(ms, 0x04, pkcs1.Length);
            ms.Write(pkcs1, 0, pkcs1.Length);
            return WrapSeq(ms.ToArray());
        }
    }

    private static void WriteInt(Stream ms, byte[] bytes) {
        int start = 0;
        while (start < bytes.Length - 1 && bytes[start] == 0) start++;
        byte[] val = new byte[bytes.Length - start];
        Array.Copy(bytes, start, val, 0, val.Length);
        if ((val[0] & 0x80) != 0) {
            byte[] padded = new byte[val.Length + 1];
            Array.Copy(val, 0, padded, 1, val.Length);
            val = padded;
        }
        WriteLen(ms, 0x02, val.Length);
        ms.Write(val, 0, val.Length);
    }

    private static byte[] WrapSeq(byte[] body) {
        using (var ms = new MemoryStream()) {
            WriteLen(ms, 0x30, body.Length);
            ms.Write(body, 0, body.Length);
            return ms.ToArray();
        }
    }

    private static void WriteLen(Stream ms, byte tag, int len) {
        ms.WriteByte(tag);
        if (len < 128) {
            ms.WriteByte((byte)len);
        } else if (len < 256) {
            ms.WriteByte(0x81);
            ms.WriteByte((byte)len);
        } else {
            ms.WriteByte(0x82);
            ms.WriteByte((byte)(len >> 8));
            ms.WriteByte((byte)(len & 0xFF));
        }
    }
}
'@
    $keyPem = [Pkcs8Exporter]::ExportPkcs8($params)
}

Write-Host "=== CERT PEM (client_cert.pfx) ===" -ForegroundColor Cyan
Write-Host $certPem
Write-Host ""
Write-Host "=== KEY PEM (client_cert.pfx) ===" -ForegroundColor Cyan
Write-Host $keyPem

$certPem | Out-File 'C:\Code\smart_tv_remote\pfx_cert.pem' -Encoding ASCII
$keyPem | Out-File 'C:\Code\smart_tv_remote\pfx_key.pem' -Encoding ASCII
