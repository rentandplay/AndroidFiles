[CmdletBinding()]
param(
    [ValidateSet('WiFi', 'USB', 'Emulator')]
    [string]$Connection = 'WiFi',
    [string]$ApiHost,
    [ValidateRange(1, 65535)]
    [int]$ApiPort = 3000,
    [string]$DeviceId,
    [switch]$BuildApk,
    [switch]$Install,
    [switch]$AllDevices
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Install -and -not $BuildApk) {
    throw 'Use -BuildApk -Install to build and install a local APK.'
}
if ($AllDevices -and (-not $Install -or $DeviceId)) {
    throw 'Use -AllDevices with -BuildApk -Install, without -DeviceId.'
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
        $ipv4 = $properties.UnicastAddresses | Where-Object {
            $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            -not $_.Address.IsLoopback -and
            -not $_.Address.ToString().StartsWith('169.254.')
        } | Select-Object -First 1
        if (-not $ipv4) { continue }

        # Windows Mobile Hotspot has no gateway on its own virtual adapter.
        $isHotspot = $adapter.Description -match 'Wi-Fi Direct Virtual Adapter' -and
            $ipv4.Address.ToString() -eq '192.168.137.1'
        if (-not $hasIpv4Gateway -and -not $isHotspot) { continue }

        [PSCustomObject]@{
            Priority = if ($isHotspot) { 0 } elseif ($adapter.Name -match 'wi-?fi|wlan|wireless') { 1 } else { 2 }
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
    # Android Studio can use an SDK outside the default user-profile folder.
    $localProperties = Join-Path $projectRoot 'android\local.properties'
    if (Test-Path -LiteralPath $localProperties) {
        $sdkSetting = Get-Content -LiteralPath $localProperties |
            Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
        if ($sdkSetting) {
            $projectSdk = $sdkSetting.Substring('sdk.dir='.Length).Trim().Replace('\\', '\').Replace('\:', ':').Replace('\ ', ' ')
            $projectAdb = Join-Path $projectSdk 'platform-tools\adb.exe'
            if (Test-Path -LiteralPath $projectAdb) { return $projectAdb }
        }
    }

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
        $installTargets = @($DeviceId)
        if ($AllDevices) {
            $deviceList = & $adbPath devices
            if ($LASTEXITCODE -ne 0) { throw 'Could not list Android devices.' }
            $installTargets = @($deviceList | ForEach-Object {
                if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] }
            })
            if ($installTargets.Count -eq 0) {
                throw 'No authorized Android devices found. Connect the phones by USB and allow USB debugging.'
            }
        }
        foreach ($targetDevice in $installTargets) {
            $adbArgs = @()
            if ($targetDevice) { $adbArgs += @('-s', $targetDevice) }
            Write-Host "Installing APK ($apiBaseUrl) on device: $targetDevice"
            & $adbPath @adbArgs install -r $localApk
            if ($LASTEXITCODE -ne 0) { throw "APK installation failed for device '$targetDevice' with exit code $LASTEXITCODE." }
        }
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
