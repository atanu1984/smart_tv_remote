$subnet = "192.168.0"
Write-Host "Scanning network $subnet.0/24 for Android TV (port 6467)..." -ForegroundColor Cyan

$jobs = @()
1..254 | ForEach-Object {
    $ip = "$subnet.$_"
    $jobs += [System.Net.Sockets.TcpClient]::new().BeginConnect($ip, 6467, $null, $ip)
}

$foundIp = $null
foreach ($job in $jobs) {
    if ($job.AsyncWaitHandle.WaitOne(400, $false)) {
        $ip = $job.AsyncState
        Write-Host "FOUND OPEN PORT 6467 AT IP: $ip" -ForegroundColor Green
        $foundIp = $ip
        break
    }
}

if (-not $foundIp) {
    Write-Host "No device responding on port 6467 found. Checking port 6466..." -ForegroundColor Yellow
    $jobs6466 = @()
    1..254 | ForEach-Object {
        $ip = "$subnet.$_"
        $jobs6466 += [System.Net.Sockets.TcpClient]::new().BeginConnect($ip, 6466, $null, $ip)
    }
    foreach ($job in $jobs6466) {
        if ($job.AsyncWaitHandle.WaitOne(400, $false)) {
            $ip = $job.AsyncState
            Write-Host "FOUND OPEN PORT 6466 AT IP: $ip" -ForegroundColor Green
            $foundIp = $ip
            break
        }
    }
}

if ($foundIp) {
    Write-Host "Testing mTLS Handshake on ${foundIp}:6467..." -ForegroundColor Cyan
    $pfxPath = "C:\Code\smart_tv_remote\client_cert.pfx"
    $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    $certCollection.Import($pfxPath, "temp1234", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient($foundIp, 6467)
        $callback = [System.Net.Security.RemoteCertificateValidationCallback] { $true }
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $callback)
        $sslStream.AuthenticateAsClient($foundIp, $certCollection, [System.Security.Authentication.SslProtocols]::Tls12, $false)
        Write-Host "SUCCESS: mTLS Handshake completed cleanly with ${foundIp}:6467!" -ForegroundColor Green
        Write-Host "Server Cert Subject: $($sslStream.RemoteCertificate.Subject)" -ForegroundColor Yellow
        $sslStream.Close()
        $tcpClient.Close()
    } catch {
        Write-Host "Handshake Error on ${foundIp}: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "No Google TV found on ports 6467 or 6466 in $subnet.1-254." -ForegroundColor Red
}
