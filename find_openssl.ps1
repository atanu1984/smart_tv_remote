# Use certutil to export the private key since PowerShell's RSACng has export restrictions
$pfxPath  = 'C:\Code\smart_tv_remote\client_cert.pfx'
$pemOut   = 'C:\Code\smart_tv_remote\client_combined.pem'

# Export combined PEM via certutil
certutil -exportPFX -p "temp1234" My 72F1A8CA3B2583513E2D207897F8DFF48654B342 'C:\Code\smart_tv_remote\client_export.pfx' 2>&1

# Use openssl if available
$opensslPaths = @("C:\Program Files\Git\usr\bin\openssl.exe", "C:\Program Files\OpenSSL-Win64\bin\openssl.exe", "openssl")
$openssl = $null
foreach ($p in $opensslPaths) {
    if (Test-Path $p -ErrorAction SilentlyContinue) { $openssl = $p; break }
    try { & $p version 2>&1 | Out-Null; $openssl = $p; break } catch {}
}

if ($openssl) {
    Write-Host "Found openssl at: $openssl" -ForegroundColor Green
    & $openssl pkcs12 -in $pfxPath -out $pemOut -nodes -passin pass:temp1234
    Write-Host "Combined PEM written to: $pemOut"
} else {
    Write-Host "openssl not found. Trying git-bundled openssl..." -ForegroundColor Yellow
    $gitOpenssl = "C:\Program Files\Git\mingw64\bin\openssl.exe"
    if (Test-Path $gitOpenssl) {
        & $gitOpenssl pkcs12 -in $pfxPath -out $pemOut -nodes -passin pass:temp1234
        Write-Host "Done via git openssl: $pemOut"
    } else {
        Write-Host "No openssl found. Will use alternative approach." -ForegroundColor Red
        # List available openssl locations
        Get-ChildItem "C:\Program Files\Git" -Recurse -Filter "openssl.exe" -ErrorAction SilentlyContinue | Select-Object FullName
    }
}
