$pem = Get-Content "C:\Code\smart_tv_remote\new_client_cert.pem" -Raw
$b64 = $pem -replace '-----[A-Z ]+-----', '' -replace '\s', ''
$der = [Convert]::FromBase64String($b64)

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($der)
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
$realMod = $rsa.ExportParameters($false).Modulus

Write-Host "REAL Modulus (first 16 bytes): " (($realMod[0..15] | ForEach-Object { "{0:X2}" -f $_ }) -join " ")

# Correct ASN.1 parser:
# Look for RSA OID (1.2.840.113549.1.1.1 = 2A 86 48 86 F7 0D 01 01 01)
# IMMEDIATELY AFTER the AlgorithmIdentifier (OID + NULL), the NEXT TLV element in SubjectPublicKeyInfo IS the BIT STRING (0x03).
$rsaOid = @(0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01)
$oidPos = -1
for ($i = 0; $i -le $der.Length - $rsaOid.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $rsaOid.Length; $j++) {
        if ($der[$i + $j] -ne $rsaOid[$j]) { $match = $false; break }
    }
    if ($match) { $oidPos = $i; break }
}

Write-Host "RSA OID at $oidPos"

# AlgorithmIdentifier starts before OID (tag 0x30). The OID is inside AlgorithmIdentifier.
# After AlgorithmIdentifier sequence ends, the VERY NEXT byte is tag 0x03 (BIT STRING).
# AlgorithmIdentifier is tag 0x30, len 0x0D: 30 0D 06 09 [OID...] 05 00
# So OID starts at oidPos. OID length is 9. NULL tag (0x05 0x00) takes 2 bytes.
# So AlgorithmIdentifier ends at oidPos + 9 + 2 = oidPos + 11.
# The BIT STRING tag 0x03 is EXACTLY at oidPos + 11!
$bitStringPos = $oidPos + 11
Write-Host "BIT STRING tag byte at $bitStringPos : 0x{0:X2}" -f $der[$bitStringPos]

function Read-Len([byte[]]$d, [int]$p) {
    $p++
    [int]$l = $d[$p++]
    if ($l -band 0x80) {
        $nb = $l -band 0x7F
        $l = 0
        for ($k = 0; $k -lt $nb; $k++) { $l = ($l -shl 8) -bor $d[$p++] }
    }
    return @($p, $l)
}

$res1 = Read-Len $der $bitStringPos
$bitValStart = $res1[0]
$rsaSeq = $bitValStart + 1 # skip 0x00 unused bits

Write-Host "RSAPublicKey SEQUENCE tag at $rsaSeq : 0x{0:X2}" -f $der[$rsaSeq]

$res2 = Read-Len $der $rsaSeq
$modTagPos = $res2[0]

Write-Host "Modulus INTEGER tag at $modTagPos : 0x{0:X2}" -f $der[$modTagPos]

$res3 = Read-Len $der $modTagPos
$mStart = $res3[0]
$mLen = $res3[1]

$extractedMod = $der[$mStart..($mStart + $mLen - 1)]
if ($extractedMod[0] -eq 0x00) {
    $extractedMod = $extractedMod[1..($extractedMod.Length - 1)]
}

Write-Host "EXTRACTED Modulus (first 16 bytes): " (($extractedMod[0..15] | ForEach-Object { "{0:X2}" -f $_ }) -join " ")

$match = $true
for ($x = 0; $x -lt 256; $x++) {
    if ($realMod[$x] -ne $extractedMod[$x]) { $match = $false; break }
}

if ($match) {
    Write-Host "`n🎉 SUCCESS! FIXED ASN.1 PARSER MATCHES REAL RSA MODULUS 100%!" -ForegroundColor Green
} else {
    Write-Host "`n❌ STILL MISMATCH!" -ForegroundColor Red
}
