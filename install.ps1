# ============================================================================
#  SUNSHINE CUSTOM HOST - UNIFIED INSTALLER
#  Installs: Sunshine, Playnite, Virtual Display Driver
#  Configures: Hardened MST-Aware Scripts, AdvancedRun, Custom Apps
# ============================================================================
$ErrorActionPreference = "Stop"
$ToolsDir = "C:\Sunshine-Tools"
$SunshineConfigDir = "C:\Program Files\Sunshine\config"

# Check Admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Please run this script as Administrator!"
    exit
}

Write-Host ">>> STARTING UNIFIED INSTALLATION..." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# PHASE 1: CORE SOFTWARE INSTALLATION (Winget / Manual)
# ---------------------------------------------------------------------------

# 1. SUNSHINE
if (-not (Get-Service "Sunshine Service" -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Sunshine..." -ForegroundColor Yellow
    winget install --id LizardByte.Sunshine -e --silent --accept-package-agreements --accept-source-agreements
    # Wait for service to register
    Start-Sleep -Seconds 5
} else {
    Write-Host "Sunshine is already installed." -ForegroundColor Green
}

# 2. PLAYNITE
if (-not (Test-Path "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe")) {
    Write-Host "Installing Playnite..." -ForegroundColor Yellow
    winget install --id Playnite.Playnite -e --silent --accept-package-agreements --accept-source-agreements
} else {
    Write-Host "Playnite is already installed." -ForegroundColor Green
}

# 3. VIRTUAL DISPLAY DRIVER (IddSampleDriver)
# We check if the device exists in PnP
$vddCheck = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" }
if (-not $vddCheck) {
    Write-Host "Installing Virtual Display Driver..." -ForegroundColor Yellow
    
    $vddZip = "$env:TEMP\vdd_driver.zip"
    $vddDir = "C:\IddSampleDriver"
    
    # Download Latest MikeTheTech Driver (Stable)
    Invoke-WebRequest -Uri "https://github.com/itsmikethetech/Virtual-Display-Driver/releases/download/23.12.2.1/IddSampleDriver.zip" -OutFile $vddZip
    
    # Extract
    if (Test-Path $vddDir) { Remove-Item $vddDir -Recurse -Force }
    Expand-Archive -Path $vddZip -DestinationPath "C:\" -Force # Usually extracts to C:\IddSampleDriver
    
    # Install Cert & Driver
    Write-Host "Trusting Driver Certificate..."
    certutil -addstore -f "TrustedPublisher" "$vddDir\IddSampleDriver.cer"
    
    Write-Host "Adding Device Root Node..."
    # We use nefconw if available, or the included bat helpers. 
    # For reliability, we shell out to the install.bat usually included, or pnputil.
    # Since this driver is tricky, we assume the user might need to click "Install" if silent fails, 
    # but we try pnputil first.
    pnputil /add-driver "$vddDir\IddSampleDriver.inf" /install
    
    Write-Host "VDD Installed. (If it fails, run C:\IddSampleDriver\install.bat manually)"
} else {
    Write-Host "Virtual Display Driver is already present." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# PHASE 2: CUSTOM TOOLS DEPLOYMENT (Sunshine-Tools)
# ---------------------------------------------------------------------------

if (-not (Test-Path $ToolsDir)) { New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null }

$Downloads = @(
    @{ Name="MultiMonitorTool"; Url="https://www.nirsoft.net/utils/multimonitortool-x64.zip" },
    @{ Name="AdvancedRun";      Url="https://www.nirsoft.net/utils/advancedrun-x64.zip" },
    @{ Name="WinDisplayMgr";    Url="https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip" }
)

foreach ($tool in $Downloads) {
    $zipPath = "$ToolsDir\$($tool.Name).zip"
    # Only download if missing to save time on re-runs
    if (-not (Test-Path "$ToolsDir\$($tool.Name).exe") -and -not (Test-Path "$ToolsDir\WindowsDisplayManager")) {
        Write-Host "Downloading $($tool.Name)..."
        Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
        Remove-Item $zipPath -Force
    }
}

# Fix WindowsDisplayManager Folder Name
$gitHubFolder = Join-Path $ToolsDir "WindowsDisplayManager-master"
$targetFolder = Join-Path $ToolsDir "WindowsDisplayManager"
if (Test-Path $gitHubFolder) {
    if (Test-Path $targetFolder) { Remove-Item $targetFolder -Recurse -Force }
    Rename-Item -Path $gitHubFolder -NewName "WindowsDisplayManager"
}

# ---------------------------------------------------------------------------
# PHASE 3: WRITE CONFIGURATION FILES
# ---------------------------------------------------------------------------
Write-Host "Writing Custom Configurations..."

# 1. Setup Script (Hardened)
$SetupScript = @'
$LogPath = "C:\Sunshine-Tools\sunvdm_log.txt"
Start-Transcript -Path $LogPath -Append
function Log-Message { param([string]$msg) Write-Host "$(Get-Date -Format 'HH:mm:ss') - $msg" }

try {
    Log-Message "--- SETUP STARTED ---"
    $ScriptPath = "C:\Sunshine-Tools"
    $MultiTool = Join-Path $ScriptPath "MultiMonitorTool.exe"
    $ConfigBackup = Join-Path $ScriptPath "monitor_config.cfg"
    $CsvPath = Join-Path $ScriptPath "current_monitors.csv"

    # 1. HARDCODED TARGET (4K 60FPS)
    $width = 3840; $height = 2160; $fps = 60
    Log-Message "Target: $width x $height @ $fps"

    # 2. Backup Current State
    Start-Process -FilePath $MultiTool -ArgumentList "/SaveConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden
    if (-not (Test-Path $ConfigBackup)) { Throw "Config backup failed." }

    # 3. Enable Virtual Display
    Log-Message "Enabling VDD..."
    $vdd_pnp = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" -or $_.FriendlyName -match "Virtual Display" } | Select-Object -First 1
    if (-not $vdd_pnp) { Throw "Virtual Display Driver not found." }
    $vdd_pnp | Enable-PnpDevice -Confirm:$false -ErrorAction Stop

    # 4. Wait for Registration
    Log-Message "Waiting for VDD..."
    $max_retries = 20
    $virtual_mon = $null
    do {
        Start-Process -FilePath $MultiTool -ArgumentList "/scomma `"$CsvPath`"" -Wait -WindowStyle Hidden
        if (Test-Path $CsvPath) {
            $monitors = Import-Csv $CsvPath
            $virtual_mon = $monitors | Where-Object { $_.'MonitorID' -match "MTT" -or $_.'Monitor Name' -match "VDD" }
        }
        if ($virtual_mon) { break }
        Start-Sleep -Milliseconds 250
    } while ($max_retries-- -gt 0)
    if (-not $virtual_mon) { Throw "Timeout: VDD never appeared." }

    # 5. Switch Primary
    Log-Message "Setting Primary: $($virtual_mon.Name)"
    Start-Process -FilePath $MultiTool -ArgumentList "/SetPrimary $($virtual_mon.Name)" -Wait -WindowStyle Hidden
    Start-Process -FilePath $MultiTool -ArgumentList "/Enable $($virtual_mon.Name)" -Wait -WindowStyle Hidden

    # 6. Disable Physical (MST Optimized)
    Log-Message "Disabling Physical Monitors..."
    Start-Process -FilePath $MultiTool -ArgumentList "/scomma `"$CsvPath`"" -Wait -WindowStyle Hidden
    $monitors = Import-Csv $CsvPath
    # Disable Display 5 (Hub) LAST
    $sorted = $monitors | Sort-Object { if ($_.Name -eq "\\.\DISPLAY5") { 1 } else { 0 } }

    foreach ($m in $sorted) {
        if ($m.Active -eq "Yes" -and $m.Name -ne $virtual_mon.Name) {
            Log-Message " -> Disabling $($m.Name)"
            Start-Process -FilePath $MultiTool -ArgumentList "/disable $($m.Name)" -Wait -WindowStyle Hidden
        }
    }

    # 7. Resolution
    Import-Module (Join-Path $ScriptPath "WindowsDisplayManager") -ErrorAction SilentlyContinue
    $displays = WindowsDisplayManager\GetAllPotentialDisplays
    $vdDisplay = $displays | Where-Object { $_.source.description -eq $vdd_pnp.FriendlyName } | Select-Object -First 1
    if ($vdDisplay) { $vdDisplay.SetResolution([int]$width, [int]$height, [int]$fps) }

    Log-Message "--- SETUP COMPLETE ---"

} catch {
    Log-Message "CRITICAL ERROR: $($_.Exception.Message)"
    Log-Message "ROLLING BACK..."
    Start-Process -FilePath $MultiTool -ArgumentList "/LoadConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden
    Stop-Transcript
    exit 1
}
Stop-Transcript
'@
$SetupScript | Set-Content "$ToolsDir\setup_sunvdm.ps1" -Encoding UTF8

# 2. Teardown Script (Hardened)
$TeardownScript = @'
$LogPath = "C:\Sunshine-Tools\sunvdm_log.txt"
Start-Transcript -Path $LogPath -Append
function Log-Message { param([string]$msg) Write-Host "$(Get-Date -Format 'HH:mm:ss') - $msg" }

try {
    Log-Message "--- TEARDOWN STARTED ---"
    $ScriptPath = "C:\Sunshine-Tools"
    $MultiTool = Join-Path $ScriptPath "MultiMonitorTool.exe"
    $ConfigBackup = Join-Path $ScriptPath "monitor_config.cfg"

    # 1. Disable VDD
    Log-Message "Disabling VDD..."
    $vdd_pnp = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" -or $_.FriendlyName -match "Virtual Display" } | Select-Object -First 1
    if ($vdd_pnp) { $vdd_pnp | Disable-PnpDevice -Confirm:$false -ErrorAction Continue }

    # 2. Restore Physical
    Log-Message "Restoring Config..."
    if (Test-Path $ConfigBackup) {
        Start-Process -FilePath $MultiTool -ArgumentList "/LoadConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden
    }

    # 3. Enforce Hub Primary
    Log-Message "Enforcing Primary: \\.\DISPLAY5"
    Start-Process -FilePath $MultiTool -ArgumentList "/SetPrimary \\.\DISPLAY5" -Wait -WindowStyle Hidden
    Start-Process -FilePath $MultiTool -ArgumentList "/Enable \\.\DISPLAY5" -Wait -WindowStyle Hidden

    Log-Message "--- TEARDOWN COMPLETE ---"

} catch {
    Log-Message "ERROR: $($_.Exception.Message)"
    # Emergency Force
    & $MultiTool /Enable \\.\DISPLAY5
    & $MultiTool /SetPrimary \\.\DISPLAY5
}
Stop-Transcript
'@
$TeardownScript | Set-Content "$ToolsDir\teardown_sunvdm.ps1" -Encoding UTF8

# 3. AdvancedRun Configs (.cfg)
# Global Monitor Configs (Admin)
$cfg_setup = "[General]`r`nExeFilename=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`r`nCommandLine=-ExecutionPolicy Bypass -File `"C:\Sunshine-Tools\setup_sunvdm.ps1`"`r`nStartDirectory=C:\Sunshine-Tools`r`nRunAs=1`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
$cfg_setup | Set-Content "$ToolsDir\cfg_setup.cfg"

$cfg_teardown = "[General]`r`nExeFilename=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`r`nCommandLine=-ExecutionPolicy Bypass -File `"C:\Sunshine-Tools\teardown_sunvdm.ps1`"`r`nStartDirectory=C:\Sunshine-Tools`r`nRunAs=1`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
$cfg_teardown | Set-Content "$ToolsDir\cfg_teardown.cfg"

# App Configs (User Level)
$Apps = @{
    "cfg_steam.cfg"    = "C:\Windows\explorer.exe|steam://open/bigpicture|C:\Windows|0|3"
    "cfg_xbox.cfg"     = "C:\Windows\explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\Windows|0|3"
    "cfg_playnite.cfg" = "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe||$env:LOCALAPPDATA\Playnite|0|3"
    "cfg_esde.cfg"     = "$env:APPDATA\EmuDeck\Emulators\ES-DE\ES-DE.exe||$env:APPDATA\EmuDeck\Emulators\ES-DE|0|3"
    "cfg_sleep.cfg"    = "C:\Windows\System32\rundll32.exe|powrprof.dll,SetSuspendState 0,1,0|C:\Windows\System32|1|0"
    "cfg_restart.cfg"  = "C:\Windows\System32\shutdown.exe|/r /t 0|C:\Windows\System32|1|0"
    "cfg_taskmgr.cfg"  = "C:\Windows\System32\Taskmgr.exe||C:\Windows\System32|1|1"
}

foreach ($key in $Apps.Keys) {
    $parts = $Apps[$key].Split("|")
    $content = "[General]`r`nExeFilename=$($parts[0])`r`nCommandLine=$($parts[1])`r`nStartDirectory=$($parts[2])`r`nRunAs=$($parts[3])`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=$($parts[4])"
    $content | Set-Content "$ToolsDir\$key"
}

# ---------------------------------------------------------------------------
# PHASE 4: DEPLOY SUNSHINE CONFIG
# ---------------------------------------------------------------------------
Write-Host "Deploying Sunshine Configs..."

# Sunshine Config (Global)
$confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_setup.cfg","undo":"C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_teardown.cfg"}]'
$confContent | Set-Content "$SunshineConfigDir\sunshine.conf" -Encoding UTF8

# Apps JSON (Smorgasbord)
$appsContent = @'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png" },
    { "name": "Steam Big Picture", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_steam.cfg", "undo": "" } ], "image-path": "steam.png" },
    { "name": "Xbox (Game Pass)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_xbox.cfg", "undo": "" } ], "image-path": "xbox.png" },
    { "name": "Playnite", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_playnite.cfg", "undo": "" } ], "image-path": "playnite.png" },
    { "name": "EmulationStation", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_esde.cfg", "undo": "" } ], "image-path": "esde.png" },
    { "name": "Task Manager (Rescue)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_taskmgr.cfg", "undo": "" } ], "image-path": "taskmgr.png" },
    { "name": "Sleep PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_sleep.cfg", "undo": "" } ], "image-path": "sleep.png" },
    { "name": "Restart PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_restart.cfg", "undo": "" } ], "image-path": "restart.png" }
  ]
}
'@
$appsContent | Set-Content "$SunshineConfigDir\apps.json" -Encoding UTF8

# ---------------------------------------------------------------------------
# PHASE 5: FINAL CLEANUP
# ---------------------------------------------------------------------------
Write-Host "Unblocking files..."
Get-ChildItem -Path $ToolsDir -Recurse | Unblock-File

Write-Host "Restarting Sunshine Service..."
Stop-Service "Sunshine Service" -ErrorAction SilentlyContinue
Get-Process "sunshine" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service "Sunshine Service" -ErrorAction SilentlyContinue

Write-Host ">>> COMPLETE! Your Custom Sunshine Host is Ready. <<<" -ForegroundColor Green