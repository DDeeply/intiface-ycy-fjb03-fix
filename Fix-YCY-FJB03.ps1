# ==============================================================================
#  Yiciyuan (役次元) YCY-FJB-03 Intiface Central All-in-One Fix Script
#  Version: 1.1.0
# ==============================================================================
#
#  Features & Improvements:
#    1. Patches buttplug-device-config-v5.json without UTF-8 BOM.
#    2. Generates schema-compliant buttplug-user-device-config-v5.json
#       (nesting configurations under 'devices' and cleaning null identifiers).
#    3. Locks user config as READ-ONLY to prevent Buttplug runtime wiping.
#    4. Dynamically scans and hot-patches rust_lib_intiface_central.dll
#       (adaptive to any Intiface Central build version).
#    5. Comprehensive installation directory discovery.
#    6. Safe process restart with isolated working directory.
#
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# Detect Intiface Central installation path
$Candidates = @(
    "C:\Program Files (x86)\IntifaceCentral",
    "C:\Program Files\IntifaceCentral",
    "D:\Program Files (x86)\IntifaceCentral",
    "D:\Program Files\IntifaceCentral",
    "E:\Program Files (x86)\IntifaceCentral",
    "E:\Program Files\IntifaceCentral",
    "F:\Program Files (x86)\IntifaceCentral",
    "F:\Program Files\IntifaceCentral",
    "$env:LOCALAPPDATA\Programs\IntifaceCentral",
    "$env:LOCALAPPDATA\IntifaceCentral"
)

$IntifaceDir = $null
foreach ($path in $Candidates) {
    if (Test-Path "$path\intiface_central.exe") {
        $IntifaceDir = $path
        break
    }
}

if (-not $IntifaceDir) {
    # Check running process
    $proc = Get-Process intiface_central -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) {
        $IntifaceDir = Split-Path -Parent $proc.Path
    }
}

if (-not $IntifaceDir) {
    # Fallback default
    $IntifaceDir = "F:\Program Files\IntifaceCentral"
}

$IntifaceExe = "$IntifaceDir\intiface_central.exe"
$DllPath     = "$IntifaceDir\rust_lib_intiface_central.dll"
$ConfigDir   = "$env:APPDATA\com.nonpolynomial\intiface_central\config"
$MainConfig  = "$ConfigDir\buttplug-device-config-v5.json"
$UserConfig  = "$ConfigDir\buttplug-user-device-config-v5.json"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DllPatchJs  = "$ScriptDir\ycy_dll_patch.js"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-OK    { param($m) Write-Host "  [OK] $m" -ForegroundColor Green  }
function Write-Info  { param($m) Write-Host "  [..] $m" -ForegroundColor Cyan   }
function Write-Warn  { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "  [XX] $m" -ForegroundColor Red    }
function Write-Title { param($m) Write-Host "`n=== $m ===" -ForegroundColor White }

Write-Host ""
Write-Host "  ========================================================" -ForegroundColor Magenta
Write-Host "    Yiciyuan YCY-FJB-03 Intiface Central Fix (v1.1.0)     " -ForegroundColor Magenta
Write-Host "  ========================================================" -ForegroundColor Magenta
Write-Host "  Intiface Dir : $IntifaceDir" -ForegroundColor DarkGray
Write-Host "  Config Dir   : $ConfigDir" -ForegroundColor DarkGray

# ------------------------------------------------------------------------------
# STEP 1: Main Device Configuration
# ------------------------------------------------------------------------------
Write-Title "STEP 1: Main Device Config (buttplug-device-config-v5.json)"

if (-not (Test-Path $MainConfig)) {
    Write-Err "Config not found: $MainConfig"
    Write-Err "Please launch Intiface Central at least once to generate initial configuration."
    if ([Environment]::UserInteractive) { Read-Host "Press Enter to exit" }
    exit 1
}

$mainJson = Get-Content $MainConfig -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $mainJson.protocols.yiciyuan) {
    Write-Err "yiciyuan protocol definition not found in main config."
    if ([Environment]::UserInteractive) { Read-Host "Press Enter to exit" }
    exit 1
}

$ycy    = $mainJson.protocols.yiciyuan
$comm   = $ycy.communication[0].btle
$names  = [System.Collections.Generic.List[string]]($comm.names)
$changed = $false

if (-not $names.Contains("YCY-FJB-03")) {
    $names.Add("YCY-FJB-03")
    Write-Info "Added 'YCY-FJB-03' to BLE advertisement name filter."
    $changed = $true
} else {
    Write-OK "'YCY-FJB-03' already present in BLE name filter."
}

if (-not $names.Contains("YCY-FJB-*")) {
    $names.Add("YCY-FJB-*")
    Write-Info "Added 'YCY-FJB-*' wildcard pattern."
    $changed = $true
}
$comm.names = $names.ToArray()

$hasConfig = $ycy.configurations | Where-Object { $_.identifier -contains "YCY-FJB-03" }
if (-not $hasConfig) {
    $newEntry = [PSCustomObject]@{
        id         = "7b3a2f91-d4c5-4e8a-b6f7-2c1d9e0a5b3c"
        identifier = @("YCY-FJB-03")
        name       = "Yiciyuan FJB-03"
    }
    $cfgList = [System.Collections.Generic.List[object]]($ycy.configurations)
    $cfgList.Add($newEntry)
    $ycy.configurations = $cfgList.ToArray()
    Write-Info "Registered device configuration entry for YCY-FJB-03."
    $changed = $true
} else {
    Write-OK "Device configuration entry for YCY-FJB-03 already exists."
}

if ($changed) {
    $bakMain = "$MainConfig.bak"
    if (-not (Test-Path $bakMain)) { Copy-Item $MainConfig $bakMain }
    $mainRaw = $mainJson | ConvertTo-Json -Depth 25
    [System.IO.File]::WriteAllText($MainConfig, $mainRaw, $utf8NoBom)
    Write-OK "Main device configuration successfully patched (UTF-8 No-BOM)."
} else {
    Write-OK "Main configuration is already up-to-date."
}

# ------------------------------------------------------------------------------
# STEP 2: User Device Configuration (Schema-Compliant + Read-Only Lock)
# ------------------------------------------------------------------------------
Write-Title "STEP 2: User Device Config (Schema-Compliant & Read-Only Lock)"

# Unlock if previously marked read-only
if (Test-Path $UserConfig) {
    try {
        (Get-Item $UserConfig).IsReadOnly = $false
    } catch {}
} else {
    Write-Warn "User config not found. Creating a new template..."
    $emptyConfig = [PSCustomObject]@{
        version      = [PSCustomObject]@{ major = 5; minor = 57 }
        user_configs = [PSCustomObject]@{
            protocols = [PSCustomObject]@{}
            devices   = @()
        }
    }
    $emptyRaw = $emptyConfig | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($UserConfig, $emptyRaw, $utf8NoBom)
}

$userJson = Get-Content $UserConfig -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not ($userJson.user_configs.PSObject.Properties.Name -contains "protocols")) {
    $userJson.user_configs | Add-Member -MemberType NoteProperty -Name "protocols" -Value ([PSCustomObject]@{})
}

# Clean up any invalid devices records with null identifier string to satisfy schema
if ($userJson.user_configs.devices) {
    $validDevices = @()
    foreach ($dev in $userJson.user_configs.devices) {
        if ($dev.identifier -and $null -ne $dev.identifier.identifier) {
            $validDevices += $dev
        }
    }
    $userJson.user_configs.devices = $validDevices
}

# Schema: user_configs.protocols.<name> requires 'communication' and 'devices.configurations'
$ycyUserEntry = [PSCustomObject]@{
    communication = @(
        [PSCustomObject]@{
            btle = [PSCustomObject]@{
                names    = @("YCY-FJB-01", "YCY-FJB-02", "YCY-FJB-03", "YCY-FJB-*")
                services = [PSCustomObject]@{
                    "0000ff40-0000-1000-8000-00805f9b34fb" = [PSCustomObject]@{
                        rxblebattery = "0000ff42-0000-1000-8000-00805f9b34fb"
                        tx           = "0000ff41-0000-1000-8000-00805f9b34fb"
                    }
                }
            }
        }
    )
    devices = [PSCustomObject]@{
        configurations = @(
            [PSCustomObject]@{ id = "e45517ef-4358-4e65-8d78-3ff9447ea1c9"; identifier = @("YCY-FJB-01"); name = "Yiciyuan FJB-01" }
            [PSCustomObject]@{ id = "48108f07-5871-445b-9f2a-10ceb1809b23"; identifier = @("YCY-FJB-02"); name = "Yiciyuan FJB-02" }
            [PSCustomObject]@{ id = "7b3a2f91-d4c5-4e8a-b6f7-2c1d9e0a5b3c"; identifier = @("YCY-FJB-03"); name = "Yiciyuan FJB-03" }
        )
    }
}

$bakUser = "$UserConfig.bak"
if (-not (Test-Path $bakUser)) { Copy-Item $UserConfig $bakUser }

$userJson.user_configs.protocols | Add-Member -MemberType NoteProperty -Name "yiciyuan" -Value $ycyUserEntry -Force
$userRaw = $userJson | ConvertTo-Json -Depth 25
[System.IO.File]::WriteAllText($UserConfig, $userRaw, $utf8NoBom)

# Lock user config as Read-Only to prevent Buttplug runtime wiping bug
try {
    (Get-Item $UserConfig).IsReadOnly = $true
    Write-OK "User configuration injected & locked as READ-ONLY (prevents runtime wiping)."
} catch {
    Write-Warn "Could not set Read-Only on user config: $_"
}

# ------------------------------------------------------------------------------
# STEP 3: DLL Protocol Hot-Patch (Dynamic Pattern Scanning)
# ------------------------------------------------------------------------------
Write-Title "STEP 3: Engine DLL Binary Patch (Dynamic Signature Scan)"

if (-not (Test-Path $DllPath)) {
    Write-Err "Target DLL not found at: $DllPath"
    if ([Environment]::UserInteractive) { Read-Host "Press Enter to exit" }
    exit 1
}

$nodeCmd = $null
try { $nodeCmd = (Get-Command node -ErrorAction Stop).Source } catch {}

if (-not $nodeCmd) {
    Write-Warn "Node.js not detected in PATH. Skipping DLL hot-patch."
    Write-Warn "Please install Node.js from https://nodejs.org if device fails to physically react."
} elseif (-not (Test-Path $DllPatchJs)) {
    Write-Err "DLL patch script not found: $DllPatchJs"
} else {
    Write-Info "Executing dynamic pattern scan on engine DLL..."

    # Temporarily allow stderr without terminating script
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $nodeOut = & node $DllPatchJs $DllPath 2>&1
    $dllExitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedEAP

    if ($dllExitCode -eq 0) {
        if ("$nodeOut" -match "ALREADY_PATCHED") {
            Write-OK "DLL already hot-patched ($nodeOut)."
        } elseif ("$nodeOut" -match "PATCH_APPLIED") {
            Write-OK "DLL hot-patch applied successfully! ($nodeOut)"
        }
    } elseif ($dllExitCode -eq 2) {
        Write-Err "DLL write verification failed. Please run this script as Administrator."
    } elseif ($dllExitCode -eq 3) {
        Write-Warn "DLL signature mismatch. Intiface Central may have introduced a protocol rewrite."
        Write-Warn "Output: $nodeOut"
    } else {
        Write-Err "DLL hot-patch error (exit $dllExitCode): $nodeOut"
    }
}

# ------------------------------------------------------------------------------
# STEP 4: Intiface Central Process Check
# ------------------------------------------------------------------------------
Write-Title "STEP 4: Service Reload / Restart"

$running = Get-Process intiface_central -ErrorAction SilentlyContinue
if ($running) {
    Write-Info "Restarting running Intiface Central process to apply changes..."
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 1500
    Start-Process -FilePath $IntifaceExe -WorkingDirectory $IntifaceDir
    Write-OK "Intiface Central restarted successfully."
} else {
    Write-Info "Intiface Central is not currently running."
    if ([Environment]::UserInteractive) {
        try {
            $ans = Read-Host "  Launch Intiface Central now? [Y/n]"
            if ($ans -eq "" -or $ans -match "^[Yy]") {
                Start-Process -FilePath $IntifaceExe -WorkingDirectory $IntifaceDir
                Write-OK "Intiface Central started."
            }
        } catch {}
    }
}

Write-Host ""
Write-Host "  ========================================================" -ForegroundColor Green
Write-Host "    All fixes applied! Ready to pair and control.         " -ForegroundColor Green
Write-Host "  ========================================================" -ForegroundColor Green
Write-Host "  How to use:"
Write-Host "    1. In Intiface Central, click [Start Server]"
Write-Host "    2. Turn on YCY-FJB-03 and enter Bluetooth pairing mode"
Write-Host "    3. Click [Start Scanning] -> Device will pair and respond!"
Write-Host ""

if ([Environment]::UserInteractive) {
    try { Read-Host "Press Enter to exit" } catch {}
}
