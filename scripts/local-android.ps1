[CmdletBinding()]
param(
    [ValidateSet('WiFi', 'USB', 'Emulator')]
    [string]$Connection = 'WiFi',
    [string]$ApiHost,
    [ValidateRange(1, 65535)]
    [int]$ApiPort = 3000,
    [string]$DeviceId,
    [switch]$BuildApk,
    [switch]$Install
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Install -and -not $BuildApk) {
    throw 'Use -BuildApk -Install to build and install a local APK.'
}

function Get-LanIpv4Address {
    $candidates = foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up -or
            $adapter.NetworkInterfaceType -in @(
                [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback,
                [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel
            )) {
            continue
        }

        $properties = $adapter.GetIPProperties()
        $hasIpv4Gateway = @($properties.GatewayAddresses | Where-Object {
            $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            $_.Address.ToString() -ne '0.0.0.0'
        }).Count -gt 0
        if (-not $hasIpv4Gateway) { continue }

        $ipv4 = $properties.UnicastAddresses | Where-Object {
            $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            -not $_.Address.IsLoopback -and
            -not $_.Address.ToString().StartsWith('169.254.')
        } | Select-Object -First 1
        if (-not $ipv4) { continue }

        [PSCustomObject]@{
            Priority = if ($adapter.Name -match 'wi-?fi|wlan|wireless') { 0 } else { 1 }
            Name     = $adapter.Name
            Address  = $ipv4.Address.ToString()
        }
    }

    $selected = $candidates | Sort-Object Priority | Select-Object -First 1
    if (-not $selected) {
        throw 'Could not find an active Wi-Fi/LAN IPv4 address. Connect this computer to the same Wi-Fi as the phone, then try again or pass -ApiHost <laptop-ip>.'
    }

    Write-Host "Using $($selected.Name): $($selected.Address)"
    return $selected.Address
}

function Get-AdbPath {
    $adbCommand = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($adbCommand) { return $adbCommand.Source }

    $sdkDirectory = if ($env:ANDROID_HOME) { $env:ANDROID_HOME }
        elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
        else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    $adbExecutable = Join-Path $sdkDirectory 'platform-tools\adb.exe'
    if (Test-Path -LiteralPath $adbExecutable) { return $adbExecutable }

    throw 'Android SDK platform-tools are required. Set ANDROID_HOME to your SDK directory.'
}

switch ($Connection) {
    'Emulator' { $ApiHost = '10.0.2.2' }
    'USB'      { $ApiHost = '127.0.0.1' }
    'WiFi'     { if (-not $ApiHost) { $ApiHost = Get-LanIpv4Address } }
}

$apiBaseUrl = "http://${ApiHost}:$ApiPort/api"
$flutterCommand = Get-Command flutter.bat -ErrorAction Stop
$adbPath = $null

if ($Connection -eq 'USB' -or $Install) {
    $adbPath = Get-AdbPath
}

if ($Connection -eq 'USB') {
    $adbArgs = @()
    if ($DeviceId) { $adbArgs += @('-s', $DeviceId) }
    & $adbPath @adbArgs reverse "tcp:$ApiPort" "tcp:$ApiPort"
    if ($LASTEXITCODE -ne 0) { throw 'adb reverse failed. Check that the phone is connected and authorized for USB debugging.' }
}

$flutterDefineArg = '--dart-define=API_BASE_URL=' + $apiBaseUrl
$flutterRunArgs = @()
if ($DeviceId) { $flutterRunArgs += @('-d', $DeviceId) }
$flutterRunArgs += $flutterDefineArg

if ($BuildApk) {
    Write-Host "Building local Android APK with API $apiBaseUrl"
    Push-Location $projectRoot
    try {
        & $flutterCommand.Source build apk --debug $flutterDefineArg
        if ($LASTEXITCODE -ne 0) { throw "Flutter APK build failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }

    $builtApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $builtApk)) { throw "Flutter reported success but the APK was not found at $builtApk." }

    $localApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-local-debug.apk'
    Copy-Item -LiteralPath $builtApk -Destination $localApk -Force
    Write-Host "Created $localApk"

    if ($Install) {
        $adbArgs = @()
        if ($DeviceId) { $adbArgs += @('-s', $DeviceId) }
        & $adbPath @adbArgs install -r $localApk
        if ($LASTEXITCODE -ne 0) { throw "APK installation failed with exit code $LASTEXITCODE." }
    }
    return
}

# A raw TCP check confirms the local API is listening without making a Firebase
# request or spending any Firestore reads.
$tcpClient = [System.Net.Sockets.TcpClient]::new()
try {
    $connect = $tcpClient.BeginConnect($ApiHost, $ApiPort, $null, $null)
    if (-not $connect.AsyncWaitHandle.WaitOne(3000)) {
        throw "Timed out reaching the backend at ${ApiHost}:$ApiPort. Start the Rent & Play backend first."
    }
    $tcpClient.EndConnect($connect)
} catch {
    throw "Cannot reach the local backend at ${ApiHost}:$ApiPort. Start the Rent & Play backend first and check Windows Firewall/private-network access. Original error: $($_.Exception.Message)"
} finally {
    $tcpClient.Dispose()
}

Write-Host "Running Flutter against $apiBaseUrl"
Write-Host 'For Wi-Fi mode, keep the phone and laptop on the same Wi-Fi and leave the backend running.'
Push-Location $projectRoot
try {
    & $flutterCommand.Source run @flutterRunArgs
    if ($LASTEXITCODE -ne 0) { throw "Flutter run failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
}
