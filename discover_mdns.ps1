# Send mDNS query for _androidtvremote2._tcp.local and _googlecast._tcp.local
Write-Host "Sending mDNS query for Android TV & Google Cast..." -ForegroundColor Cyan

$mdnsPort = 5353
$udpClient = New-Object System.Net.Sockets.UdpClient
$udpClient.Client.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)))
$udpClient.Client.ReceiveTimeout = 2000

# Query packet for _googlecast._tcp.local (PTR)
# Header: ID=0, Flags=0, QDCOUNT=1, ANCOUNT=0, NSCOUNT=0, ARCOUNT=0
[byte[]]$query = @(
    0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x0B, 0x5F, 0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, 0x63, 0x61, 0x73, 0x74, # _googlecast
    0x04, 0x5F, 0x74, 0x63, 0x70, # _tcp
    0x05, 0x6C, 0x6F, 0x63, 0x61, 0x6C, # local
    0x00,
    0x00, 0x0C, # PTR (12)
    0x00, 0x01  # IN (1)
)

$groupEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse("224.0.0.251"), $mdnsPort)
$udpClient.Send($query, $query.Length, $groupEP)

Write-Host "Listening for mDNS responses..." -ForegroundColor Cyan
$startTime = Get-Date
while (((Get-Date) - $startTime).TotalSeconds -lt 3) {
    try {
        $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $udpClient.Receive([ref]$remoteEP)
        Write-Host "mDNS Response received from $($remoteEP.Address)" -ForegroundColor Green
    } catch {
        break
    }
}
$udpClient.Close()
