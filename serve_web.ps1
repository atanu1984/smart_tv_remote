$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8085/")
$listener.Start()
Write-Host "Serving Smart TV Remote Web App at http://localhost:8085/"
while ($listener.IsListening) {
    $context = $listener.GetContext()
    $req = $context.Request
    $res = $context.Response
    $relPath = $req.Url.LocalPath
    if ($relPath -eq "/") { $relPath = "/index.html" }
    $filePath = "c:\Code\smart_tv_remote\build\web" + $relPath.Replace('/', '\')
    
    if (-not (Test-Path -PathType Leaf $filePath)) {
        $filePath = "c:\Code\smart_tv_remote\build\web\index.html"
    }

    if ($filePath.EndsWith(".html")) { $res.ContentType = "text/html" }
    elseif ($filePath.EndsWith(".js")) { $res.ContentType = "application/javascript" }
    elseif ($filePath.EndsWith(".json")) { $res.ContentType = "application/json" }
    elseif ($filePath.EndsWith(".css")) { $res.ContentType = "text/css" }
    elseif ($filePath.EndsWith(".png")) { $res.ContentType = "image/png" }

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.Close()
}
