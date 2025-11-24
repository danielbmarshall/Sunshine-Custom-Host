# ============================================================================
#  SUNSHINE CUSTOM HOST - UNIFIED INSTALLER (FINAL POLISH)
#  Installs: Sunshine, Playnite, Virtual Display Driver (Signed)
#  Configures: Hardened MST-Aware Scripts, AdvancedRun, Custom Apps
#  Visuals: High-Quality Cover Art with Browser User-Agent Headers
# ============================================================================
$ErrorActionPreference = "Stop"
$ToolsDir = "C:\Sunshine-Tools"
$SunshineConfigDir = "C:\Program Files\Sunshine\config"
$SunshineCoversDir = "$SunshineConfigDir\covers"

# Check Admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Please run this script as Administrator!"
    exit
}

Write-Host ">>> STARTING UNIFIED INSTALLATION..." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# PHASE 1: CORE SOFTWARE INSTALLATION
# ---------------------------------------------------------------------------

# 1. SUNSHINE
if (-not (Get-Service "Sunshine Service" -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Sunshine..." -ForegroundColor Yellow
    winget install --id LizardByte.Sunshine -e --silent --accept-package-agreements --accept-source-agreements
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

# 3. VIRTUAL DISPLAY DRIVER (Signed)
$vddCheck = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" }
if (-not $vddCheck) {
    Write-Host "Installing Virtual Display Driver..." -ForegroundColor Yellow
    $vddUrl = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/24.12.24/Signed-Driver-v24.12.24-x64.zip"
    $vddZip = "$env:TEMP\vdd_driver.zip"
    $vddDir = "C:\VirtualDisplayDriver"
    
    Invoke-WebRequest -Uri $vddUrl -OutFile $vddZip
    
    if (Test-Path $vddDir) { Remove-Item $vddDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $vddDir | Out-Null
    
    $tempExtract = "$env:TEMP\vdd_extract"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    Expand-Archive -Path $vddZip -DestinationPath $tempExtract -Force
    
    Get-ChildItem -Path $tempExtract -Recurse -File | Copy-Item -Destination $vddDir -Force
    
    Write-Host "Registering Driver..."
    $infFile = "$vddDir\MttVDD.inf"
    if (Test-Path $infFile) {
        pnputil /add-driver $infFile /install
        Write-Host "VDD Installed successfully." -ForegroundColor Green
    } else {
        Write-Warning "Could not find MttVDD.inf. Manual install may be required from $vddDir"
    }
} else {
    Write-Host "Virtual Display Driver is already present." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# PHASE 2: CUSTOM TOOLS DEPLOYMENT
# ---------------------------------------------------------------------------

if (-not (Test-Path $ToolsDir)) { New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null }

$Downloads = @(
    @{ Name="MultiMonitorTool"; Url="https://www.nirsoft.net/utils/multimonitortool-x64.zip" },
    @{ Name="AdvancedRun";      Url="https://www.nirsoft.net/utils/advancedrun-x64.zip" },
    @{ Name="WinDisplayMgr";    Url="https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip" }
)

foreach ($tool in $Downloads) {
    $zipPath = "$ToolsDir\$($tool.Name).zip"
    if (-not (Test-Path "$ToolsDir\$($tool.Name).exe") -and -not (Test-Path "$ToolsDir\WindowsDisplayManager")) {
        Write-Host "Downloading $($tool.Name)..."
        Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
        Remove-Item $zipPath -Force
    }
}

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

# 1. Setup Script
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

    # 1. HARDCODED TARGET (Default: 4K 60FPS)
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
    
    # Disable Display 5 (Hub) LAST to prevent MST crash
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

# 2. Teardown Script
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

    # 3. Enforce Hub Primary (Display 5)
    Log-Message "Enforcing Primary: \\.\DISPLAY5"
    Start-Process -FilePath $MultiTool -ArgumentList "/SetPrimary \\.\DISPLAY5" -Wait -WindowStyle Hidden
    Start-Process -FilePath $MultiTool -ArgumentList "/Enable \\.\DISPLAY5" -Wait -WindowStyle Hidden

    Log-Message "--- TEARDOWN COMPLETE ---"

} catch {
    Log-Message "ERROR: $($_.Exception.Message)"
    & $MultiTool /Enable \\.\DISPLAY5
    & $MultiTool /SetPrimary \\.\DISPLAY5
}
Stop-Transcript
'@
$TeardownScript | Set-Content "$ToolsDir\teardown_sunvdm.ps1" -Encoding UTF8

# 3. AdvancedRun Configs
$Apps = @{
    "cfg_setup.cfg"    = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"C:\Sunshine-Tools\setup_sunvdm.ps1`"|C:\Sunshine-Tools|1|0"
    "cfg_teardown.cfg" = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"C:\Sunshine-Tools\teardown_sunvdm.ps1`"|C:\Sunshine-Tools|1|0"
    "cfg_steam.cfg"    = "C:\Windows\explorer.exe|steam://open/bigpicture|C:\Windows|0|3"
    "cfg_xbox.cfg"     = "C:\Windows\explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\Windows|0|3"
    "cfg_playnite.cfg" = "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe||$env:LOCALAPPDATA\Playnite|0|3"
    "cfg_esde.cfg"     = "$env:APPDATA\EmuDeck\Emulators\ES-DE\ES-DE.exe||$env:APPDATA\EmuDeck\Emulators\ES-DE|0|3"
    "cfg_sleep.cfg"    = "C:\Windows\System32\rundll32.exe|powrprof.dll,SetSuspendState 0,1,0|C:\Windows\System32|1|0"
    "cfg_restart.cfg"  = "C:\Windows\System32\shutdown.exe|/r /t 0|C:\Windows\System32|1|0"
    "cfg_taskmgr.cfg"  = "C:\Windows\System32\Taskmgr.exe||C:\Windows\System32|1|1"
    "cfg_browser.cfg"  = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe|--kiosk https://www.youtube.com/tv --edge-kiosk-type=fullscreen|C:\Program Files (x86)\Microsoft\Edge\Application|0|3"
}

foreach ($key in $Apps.Keys) {
    $parts = $Apps[$key].Split("|")
    $content = "[General]`r`nExeFilename=$($parts[0])`r`nCommandLine=$($parts[1])`r`nStartDirectory=$($parts[2])`r`nRunAs=$($parts[3])`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=$($parts[4])"
    $content | Set-Content "$ToolsDir\$key"
}

# ---------------------------------------------------------------------------
# PHASE 4: DOWNLOAD COVER ART (Using Browser User-Agent & Reliable Mirrors)
# ---------------------------------------------------------------------------
Write-Host "Downloading App Cover Art..."
if (-not (Test-Path $SunshineCoversDir)) { New-Item -ItemType Directory -Force -Path $SunshineCoversDir | Out-Null }

# Note: Using Wikimedia/Github mirrors for stability and forcing a Browser UserAgent to bypass CDN blocks.
$Covers = @{
    "steam.png"    = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Steam_icon_logo.svg/512px-Steam_icon_logo.svg.png"
    "playnite.png" = "https://raw.githubusercontent.com/JosefNemec/Playnite/master/source/Playnite/Resources/Images/AppIcon.png"
    "xbox.png"     = "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Xbox_app_logo.svg/512px-Xbox_app_logo.svg.png"
    "esde.png"     = "https://gitlab.com/es-de/emulationstation-de/-/raw/master/resources/logo.png"
    "taskmgr.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Task_Manager_icon_%28Windows%29.svg/512px-Task_Manager_icon_%28Windows%29.svg.png"
    "sleep.png"    = "https://upload.wikimedia.org/wikipedia/commons/thumb/2/21/Oxygen480-actions-system-suspend.svg/512px-Oxygen480-actions-system-suspend.svg.png"
    "restart.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4c/Gnome-system-restart.svg/512px-Gnome-system-restart.svg.png"
    "browser.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Google_Chrome_icon_%28September_2014%29.svg/512px-Google_Chrome_icon_%28September_2014%29.svg.png"
    "desktop.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Windows_11_logo.svg/512px-Windows_11_logo.svg.png"
}

foreach ($img in $Covers.Keys) {
    $dest = "$SunshineCoversDir\$img"
    # Download if missing OR if previous download was 0 bytes (corrupt)
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -eq 0) {
        try {
            # The Magic Fix: Pretend to be Edge/Chrome to pass CDN filters
            Invoke-WebRequest -Uri $Covers[$img] -OutFile $dest -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            Write-Host " + Downloaded $img"
        } catch {
            Write-Warning "Failed to download $img"
        }
    }
}

# ---------------------------------------------------------------------------
# PHASE 5: DEPLOY SUNSHINE CONFIG
# ---------------------------------------------------------------------------
Write-Host "Updating Sunshine Configuration..."

if (Test-Path $SunshineConfigDir) {
    $confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_setup.cfg","undo":"C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_teardown.cfg"}]'
    $confContent | Set-Content "$SunshineConfigDir\sunshine.conf" -Encoding UTF8

    $appsContent = @'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png" },
    { "name": "Steam Big Picture", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_steam.cfg", "undo": "" } ], "image-path": "steam.png" },
    { "name": "Xbox (Game Pass)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_xbox.cfg", "undo": "" } ], "image-path": "xbox.png" },
    { "name": "Playnite", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_playnite.cfg", "undo": "" } ], "image-path": "playnite.png" },
    { "name": "EmulationStation", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_esde.cfg", "undo": "" } ], "image-path": "esde.png" },
    { "name": "YouTube TV", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_browser.cfg", "undo": "" } ], "image-path": "browser.png" },
    { "name": "Task Manager (Rescue)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_taskmgr.cfg", "undo": "" } ], "image-path": "taskmgr.png" },
    { "name": "Sleep PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_sleep.cfg", "undo": "" } ], "image-path": "sleep.png" },
    { "name": "Restart PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_restart.cfg", "undo": "" } ], "image-path": "restart.png" }
  ]
}
'@
    $appsContent | Set-Content "$SunshineConfigDir\apps.json" -Encoding UTF8
}

# ---------------------------------------------------------------------------
# PHASE 6: FINAL CLEANUP
# ---------------------------------------------------------------------------
Write-Host "Unblocking files..."
Get-ChildItem -Path $ToolsDir -Recurse | Unblock-File

Write-Host "Restarting Sunshine Service..."
Stop-Service "Sunshine Service" -ErrorAction SilentlyContinue
Get-Process "sunshine" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service "Sunshine Service" -ErrorAction SilentlyContinue

Write-Host ">>> COMPLETE! Your Custom Sunshine Host is Ready. <<<" -ForegroundColor Green
