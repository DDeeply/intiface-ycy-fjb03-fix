# ==============================================================================
#  Yiciyuan (役次元) YCY-FJB-03 Intiface Central All-in-One Fix Script
# ==============================================================================
#
#  Features:
#    1. Patches buttplug-device-config-v5.json with YCY-FJB-03 protocol spec
#    2. Configures buttplug-user-device-config-v5.json to prevent auto-update wiping
#    3. Hot-patches rust_lib_intiface_central.dll with 6-byte frames + checksum
#    4. Restarts Intiface Central (optional)
#
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# Detect Intiface Central installation path
$Candidates = @(
    "F:\Program Files\IntifaceCentral",
    "C:\Program Files\IntifaceCentral",
    "D:\Program Files\IntifaceCentral",
    "$env:LOCALAPPDATA\Programs\IntifaceCentral"
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
    $IntifaceDir = "F:\Program Files\IntifaceCentral"
}

$IntifaceExe = "$IntifaceDir\intiface_central.exe"
$DllPath     = "$IntifaceDir\rust_lib_intiface_central.dll"
$ConfigDir   = "$env:APPDATA\com.nonpolynomial\intiface_central\config"
$MainConfig  = "$ConfigDir\buttplug-device-config-v5.json"
$UserConfig  = "$ConfigDir\buttplug-user-device-config-v5.json"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DllPatchJs  = "$ScriptDir\ycy_dll_patch.js"

function Write-OK    { param($m) Write-Host "  [OK] $m" -ForegroundColor Green  }
function Write-Info  { param($m) Write-Host "  [..] $m" -ForegroundColor Cyan   }
function Write-Warn  { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "  [XX] $m" -ForegroundColor Red    }
function Write-Title { param($m) Write-Host "`n=== $m ===" -ForegroundColor White }

Write-Host ""
Write-Host "  ========================================================" -ForegroundColor Magenta
Write-Host "    Yiciyuan YCY-FJB-03 Intiface Central Auto-Fix Tool    " -ForegroundColor Magenta
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
    $mainJson | ConvertTo-Json -Depth 20 | Set-Content $MainConfig -Encoding UTF8
    Write-OK "Main device configuration successfully patched."
} else {
    Write-OK "Main configuration is already up-to-date."
}

# ------------------------------------------------------------------------------
# STEP 2: User Device Configuration (Persistent Protection)
# ------------------------------------------------------------------------------
Write-Title "STEP 2: User Device Config (Anti-Overwrite Protection)"

if (-not (Test-Path $UserConfig)) {
    Write-Warn "User config not found. Creating a new template..."
    $emptyConfig = [PSCustomObject]@{
        version      = [PSCustomObject]@{ major = 5; minor = 30 }
        user_configs = [PSCustomObject]@{
            protocols = [PSCustomObject]@{}
            devices   = @()
        }
    }
    $emptyConfig | ConvertTo-Json -Depth 10 | Set-Content $UserConfig -Encoding UTF8
}

$userJson = Get-Content $UserConfig -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not ($userJson.user_configs.PSObject.Properties.Name -contains "protocols")) {
    $userJson.user_configs | Add-Member -MemberType NoteProperty -Name "protocols" -Value ([PSCustomObject]@{})
}

$existingNames = $null
try { $existingNames = $userJson.user_configs.protocols.yiciyuan.communication[0].btle.names } catch {}

$needUserUpdate = (-not $existingNames) -or ($existingNames -notcontains "YCY-FJB-03")

if ($needUserUpdate) {
    $bakUser = "$UserConfig.bak"
    if (-not (Test-Path $bakUser)) { Copy-Item $UserConfig $bakUser }

    $ycyEntry = [PSCustomObject]@{
        communication  = @(
            [PSCustomObject]@{
                btle = [PSCustomObject]@{
                    names    = @("YCY-FJB-01","YCY-FJB-02","YCY-FJB-03","YCY-FJB-*")
                    services = [PSCustomObject]@{
                        "0000ff40-0000-1000-8000-00805f9b34fb" = [PSCustomObject]@{
                            rxblebattery = "0000ff42-0000-1000-8000-00805f9b34fb"
                            tx           = "0000ff41-0000-1000-8000-00805f9b34fb"
                        }
                    }
                }
            }
        )
        configurations = @(
            [PSCustomObject]@{ id="e45517ef-4358-4e65-8d78-3ff9447ea1c9"; identifier=@("YCY-FJB-01"); name="Yiciyuan FJB-01" }
            [PSCustomObject]@{ id="48108f07-5871-445b-9f2a-10ceb1809b23"; identifier=@("YCY-FJB-02"); name="Yiciyuan FJB-02" }
            [PSCustomObject]@{ id="7b3a2f91-d4c5-4e8a-b6f7-2c1d9e0a5b3c"; identifier=@("YCY-FJB-03"); name="Yiciyuan FJB-03" }
        )
    }

    $userJson.user_configs.protocols | Add-Member -MemberType NoteProperty -Name "yiciyuan" -Value $ycyEntry -Force
    $userJson | ConvertTo-Json -Depth 20 | Set-Content $UserConfig -Encoding UTF8
    Write-OK "User configuration protected. Auto-update will no longer remove YCY-FJB-03."
} else {
    Write-OK "User configuration already protected."
}

# ------------------------------------------------------------------------------
# STEP 3: DLL Protocol Hot-Patch (6-Byte Frame + Checksum)
# ------------------------------------------------------------------------------
Write-Title "STEP 3: Engine DLL Binary Patch (rust_lib_intiface_central.dll)"

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
    Write-Info "Verifying / patching engine DLL..."
    $nodeOut = & node $DllPatchJs $DllPath 2>&1
    $dllExitCode = $LASTEXITCODE

    if ($dllExitCode -eq 0) {
        if ("$nodeOut" -match "ALREADY_PATCHED") {
            Write-OK "DLL already hot-patched (6-byte frame + checksum active)."
        } elseif ("$nodeOut" -match "PATCH_APPLIED") {
            Write-OK "DLL hot-patch applied successfully!"
        }
    } elseif ($dllExitCode -eq 2) {
        Write-Err "DLL write verification failed. Please run this script as Administrator."
    } elseif ($dllExitCode -eq 3) {
        Write-Warn "DLL signature mismatch. Intiface Central may have been upgraded to a newer version."
        Write-Warn "Details: $nodeOut"
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
    Start-Process -FilePath $IntifaceExe
    Write-OK "Intiface Central restarted successfully."
} else {
    Write-Info "Intiface Central is not currently running."
    if ([Environment]::UserInteractive) {
        try {
            $ans = Read-Host "  Launch Intiface Central now? [Y/n]"
            if ($ans -eq "" -or $ans -match "^[Yy]") {
                Start-Process -FilePath $IntifaceExe
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
