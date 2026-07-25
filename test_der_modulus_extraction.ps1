$pem = Get-Content "C:\Code\smart_tv_remote\new_client_cert.pem" -Raw
$b64 = $pem -replace '-----[A-Z ]+-----', '' -replace '\s', ''
$der = [Convert]::FromBase64String($b64)

# Load via .NET RSACertificateExtensions
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($der)
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
$dotNetMod = $rsa.ExportParameters($false).Modulus

Write-Host "=== .NET ExportParameters Modulus ($($dotNetMod.Length) bytes) ===" -ForegroundColor Cyan
Write-Host (($dotNetMod[0..15] | ForEach-Object { "{0:X2}" -f $_ }) -join " ")

# Now run the Dart logic on $der
function Read-Asn1Len([byte[]]$d, [int]$p) {
    $p++ # skip tag
    [int]$len = $d[$p++]
    if ($len -band 0x80) {
        $numBytes = $len -band 0x7F
        $len = 0
        for ($i = 0; $i -lt $numBytes; $i++) {
            $len = ($len -shl 8) -bor $d[$p++]
        }
    }
    return @($p, $len)
}

$rsaOid = @(0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01)
$oidPos = -1
for ($i = 0; $i -le $der.Length - $rsaOid.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $rsaOid.Length; $j++) {
        if ($der[$i + $j] -ne $rsaOid[$j]) { $match = $false; break }
    }
    if ($match) { $oidPos = $i; break }
}

Write-Host "RSA OID position in DER: $oidPos"

$pos = $oidPos + $rsaOid.Length
while ($pos -lt $der.Length -and $der[$pos] -ne 0x03) { $pos++ }

$res1 = Read-Asn1Len $der $pos
$bitValueStart = $res1[0]
$rsaPkeyStart = $bitValueStart + 1 # skip 0x00

Write-Host "RSAPublicKey tag byte at $rsaPkeyStart : 0x{0:X2}" -f $der[$rsaPkeyStart]

$res2 = Read-Asn1Len $der $rsaPkeyStart
$rsaSeqStart = $res2[0]

Write-Host "Modulus tag byte at $rsaSeqStart : 0x{0:X2}" -f $der[$rsaSeqStart]

$res3 = Read-Asn1Len $der $rsaSeqStart
$modStart = $res3[0]
$modLen = $res3[1]

Write-Host "Modulus raw length from ASN.1: $modLen bytes"

$extractedMod = $der[$modStart..($modStart + $modLen - 1)]
if ($extractedMod[0] -eq 0x00) {
    $extractedMod = $extractedMod[1..($extractedMod.Length - 1)]
    Write-Host "Stripped leading 0x00 sign byte. Remaining length: $($extractedMod.Length) bytes"
}

Write-Host "`n=== Extracted Modulus ($($extractedMod.Length) bytes) ===" -ForegroundColor Yellow
Write-Host (($extractedMod[0..15] | ForEach-Object { "{0:X2}" -f $_ }) -join " ")

# Compare byte by byte
$matchCount = 0
for ($k = 0; $k -lt 256; $k++) {
    if ($dotNetMod[$k] -eq $extractedMod[$k]) { $matchCount++ }
}

if ($matchCount -eq 256) {
    Write-Host "`n✅ MODULUS MATCHES .NET 100%!" -ForegroundColor Green
} else {
    Write-Host "`n❌ MODULUS MISMATCH! Only $matchCount / 256 bytes matched!" -ForegroundColor Red
}
