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
$androidProject = Split-Path -Parent $PSScriptRoot
if ($Install -and -not $BuildApk) {
    throw 'Use -BuildApk -Install to build and install a local APK.'
}

function Get-AndroidAdb {
    $adbCommand = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($adbCommand) { return $adbCommand.Source }
    $sdkDirectory = if ($env:ANDROID_HOME) { $env:ANDROID_HOME }
        elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
        else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    $adbExecutable = Join-Path $sdkDirectory 'platform-tools\adb.exe'
    if (-not (Test-Path -LiteralPath $adbExecutable)) {
        throw 'Android SDK platform-tools are required. Set ANDROID_HOME to your SDK directory.'
    }
    return $adbExecutable
}

$adbArguments = if ($DeviceId) { @('-s', $DeviceId) } else { @() }
if ($Connection -eq 'USB') {
    $ApiHost = '127.0.0.1'
    $adbExecutable = Get-AndroidAdb
    & $adbExecutable @adbArguments reverse "tcp:$ApiPort" "tcp:$ApiPort"
    if ($LASTEXITCODE -ne 0) { throw 'Connect one authorized Android device or specify -DeviceId.' }
} elseif ($Connection -eq 'Emulator') {
    $ApiHost = '10.0.2.2'
} elseif (-not $ApiHost) {
    $networks = @(Get-NetIPConfiguration | Where-Object {
        $_.IPv4DefaultGateway -and $_.IPv4Address
    })
    $wifi = @($networks | Where-Object { $_.InterfaceAlias -match 'Wi-?Fi|Wireless' })
    $selectedNetwork = if ($wifi.Count -eq 1) { $wifi[0] }
        elseif ($networks.Count -eq 1) { $networks[0] }
        else { throw 'Specify -ApiHost with the laptop IPv4 address on the phone Wi-Fi network.' }
    $ApiHost = $selectedNetwork.IPv4Address.IPAddress | Select-Object -First 1
}

$apiBaseUrl = "http://${ApiHost}:$ApiPort/api"
$checkBaseUrl = if ($Connection -eq 'WiFi') { $apiBaseUrl } else { "http://127.0.0.1:$ApiPort/api" }
$catalog = Invoke-RestMethod -Uri "$checkBaseUrl/mobile/catalog" -TimeoutSec 20
if ($catalog.items -isnot [System.Array]) {
    throw 'The local server did not return a catalog. Start Rent & Play: Start App in VS Code.'
}
Write-Host "Local Android API: $apiBaseUrl ($($catalog.items.Count) catalog items)"
if ($Connection -eq 'WiFi') {
    Write-Host 'Keep the phone and laptop on the same Wi-Fi and leave the backend running.'
} elseif ($Connection -eq 'USB') {
    Write-Host 'Keep USB connected. Run this script again after reconnecting to restore forwarding.'
}

$flutterExecutable = (Get-Command flutter.bat -ErrorAction Stop).Source
Push-Location $androidProject
try {
    if ($BuildApk) {
        $apkDirectory = Join-Path $androidProject 'build\app\outputs\flutter-apk'
        $defaultApk = Join-Path $apkDirectory 'app-debug.apk'
        $previousApk = Join-Path $apkDirectory 'app-debug-before-local.apk'
        if ((Test-Path -LiteralPath $defaultApk) -and -not (Test-Path -LiteralPath $previousApk)) {
            Copy-Item -LiteralPath $defaultApk -Destination $previousApk
        }
        & $flutterExecutable build apk --debug "--dart-define=API_BASE_URL=$apiBaseUrl"
        if ($LASTEXITCODE -ne 0) { throw 'The local APK build failed.' }
        $localApk = Join-Path $apkDirectory 'app-local-debug.apk'
        Copy-Item -LiteralPath $defaultApk -Destination $localApk -Force
        Write-Host "Local test APK: $localApk"
        if ($Install) {
            $adbExecutable = Get-AndroidAdb
            & $adbExecutable @adbArguments install -r $localApk
            if ($LASTEXITCODE -ne 0) { throw 'The local APK could not be installed.' }
        }
    } else {
        $flutterArguments = @('run', "--dart-define=API_BASE_URL=$apiBaseUrl")
        if ($DeviceId) { $flutterArguments += @('-d', $DeviceId) }
        & $flutterExecutable @flutterArguments
        if ($LASTEXITCODE -ne 0) { throw 'The local Android run failed.' }
    }
} finally {
    Pop-Location
}
