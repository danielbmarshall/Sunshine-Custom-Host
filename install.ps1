# ============================================================================
#  SUNSHINE CUSTOM HOST - UNIFIED INSTALLER (SENIOR ENGINEER EDITION)
#  v2.0 - Optimized, Modular, and Configurable
# ============================================================================

# --- [USER CONFIGURATION AREA] ----------------------------------------------
# EDIT THESE SETTINGS TO CUSTOMIZE YOUR INSTALLATION
# ----------------------------------------------------------------------------

$GlobalConfig = @{
    # Target Resolution & Refresh Rate for Virtual Display
    ResolutionWidth  = 3840
    ResolutionHeight = 2160
    RefreshRate      = 60

    # Directory Paths
    ToolsDir         = "C:\Sunshine-Tools"
    SunshineConfig   = "C:\Program Files\Sunshine\config"
    VddInstallDir    = "C:\VirtualDisplayDriver"
}

# Apps to configure in Sunshine (Add/Remove lines here)
# Format: "ConfigName" = "ExePath | Arguments | StartDir | RunAs(0=User,1=Admin) | Window(0=Hidden,3=Max)"
$AppList = @{
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

# Cover Art to Download (Filename = URL)
$CoverArt = @{
    "steam.png"    = "https://cdn2.steamgriddb.com/grid/577720666599d0705bc8d2b939a0829c.png"
    "playnite.png" = "https://cdn2.steamgriddb.com/grid/5da02073095338066242322543599999.png"
    "xbox.png"     = "https://cdn2.steamgriddb.com/grid/52654a95df6d3e3d4b7ca34742004e9e.png"
    "esde.png"     = "https://cdn2.steamgriddb.com/grid/396953c65f239ab6079899df7be95935.png"
    "taskmgr.png"  = "https://cdn2.steamgriddb.com/grid/01b9d2062d0cb344df84b96740bf9a93.png"
    "sleep.png"    = "https://cdn2.steamgriddb.com/icon/c770e3cb26e462833e5407d373420327.png"
    "restart.png"  = "https://cdn2.steamgriddb.com/icon/225509cc69cb00262e622689762dfc08.png"
    "browser.png"  = "https://cdn2.steamgriddb.com/grid/1a787993f32b41c2408cf9244a2e33b6.png"
    "desktop.png"  = "https://cdn2.steamgriddb.com/grid/7e83e20758d6a47e2d36f6b0d0b00ba8.png"
}

# --- [END USER CONFIGURATION] -----------------------------------------------

$ErrorActionPreference = "Stop"

# Helper Function: Download and Extract Tools
function Install-Tool {
    param (
        [string]$Name,
        [string]$Url,
        [string]$CheckFile
    )
    if (-not (Test-Path $CheckFile)) {
        Write-Host "Downloading $Name..." -ForegroundColor Cyan
        $zipPath = Join-Path $env:TEMP "$Name.zip"
        try {
            Invoke-WebRequest -Uri $Url -OutFile $zipPath
            Expand-Archive -Path $zipPath -DestinationPath $GlobalConfig.ToolsDir -Force
            Remove-Item $zipPath -Force
        } catch {
            Write-Warning "Failed to download $Name. Check internet connection."
        }
    }
}

# Check Admin Rights
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Elevation Required: Please run this script as Administrator."
    exit
}

Write-Host ">>> STARTING AUTOMATED DEPLOYMENT..." -ForegroundColor Green

# ---------------------------------------------------------------------------
# PHASE 1: SOFTWARE INSTALLATION
# ---------------------------------------------------------------------------

# Install Sunshine
if (-not (Get-Service "Sunshine Service" -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Sunshine..." -ForegroundColor Yellow
    winget install --id LizardByte.Sunshine -e --silent --accept-package-agreements --accept-source-agreements
    Start-Sleep -Seconds 5
}

# Install Playnite
if (-not (Test-Path "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe")) {
    Write-Host "Installing Playnite..." -ForegroundColor Yellow
    winget install --id Playnite.Playnite -e --silent --accept-package-agreements --accept-source-agreements
}

# Install VDD (Virtual Display Driver)
$vddCheck = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" }
if (-not $vddCheck) {
    Write-Host "Installing Virtual Display Driver..." -ForegroundColor Yellow
    $vddUrl = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/24.12.24/Signed-Driver-v24.12.24-x64.zip"
    $vddZip = Join-Path $env:TEMP "vdd_driver.zip"
    
    Invoke-WebRequest -Uri $vddUrl -OutFile $vddZip
    
    if (Test-Path $GlobalConfig.VddInstallDir) { Remove-Item $GlobalConfig.VddInstallDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $GlobalConfig.VddInstallDir | Out-Null
    
    $tempExtract = Join-Path $env:TEMP "vdd_extract"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    Expand-Archive -Path $vddZip -DestinationPath $tempExtract -Force
    
    Get-ChildItem -Path $tempExtract -Recurse -File | Copy-Item -Destination $GlobalConfig.VddInstallDir -Force
    
    $infFile = Join-Path $GlobalConfig.VddInstallDir "MttVDD.inf"
    if (Test-Path $infFile) {
        Write-Host "Registering Driver..."
        pnputil /add-driver $infFile /install
    } else {
        Write-Warning "Driver INF not found. Manual install required in $($GlobalConfig.VddInstallDir)"
    }
}

# ---------------------------------------------------------------------------
# PHASE 2: TOOL DEPLOYMENT
# ---------------------------------------------------------------------------
if (-not (Test-Path $GlobalConfig.ToolsDir)) { New-Item -ItemType Directory -Force -Path $GlobalConfig.ToolsDir | Out-Null }

Install-Tool -Name "MultiMonitorTool" -Url "https://www.nirsoft.net/utils/multimonitortool-x64.zip" -CheckFile "$($GlobalConfig.ToolsDir)\MultiMonitorTool.exe"
Install-Tool -Name "AdvancedRun"      -Url "https://www.nirsoft.net/utils/advancedrun-x64.zip"      -CheckFile "$($GlobalConfig.ToolsDir)\AdvancedRun.exe"

# WindowsDisplayManager (GitHub Zip handling)
if (-not (Test-Path "$($GlobalConfig.ToolsDir)\WindowsDisplayManager")) {
    Write-Host "Downloading WindowsDisplayManager..."
    $wdmZip = Join-Path $env:TEMP "wdm.zip"
    Invoke-WebRequest -Uri "https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip" -OutFile $wdmZip
    Expand-Archive -Path $wdmZip -DestinationPath $GlobalConfig.ToolsDir -Force
    Remove-Item $wdmZip
    
    $gitHubFolder = Join-Path $GlobalConfig.ToolsDir "WindowsDisplayManager-master"
    $targetFolder = Join-Path $GlobalConfig.ToolsDir "WindowsDisplayManager"
    if (Test-Path $gitHubFolder) {
        Rename-Item -Path $gitHubFolder -NewName "WindowsDisplayManager" -Force
    }
}

# ---------------------------------------------------------------------------
# PHASE 3: GENERATE CONFIGS (Dynamic Injection)
# ---------------------------------------------------------------------------
Write-Host "Generating Custom Scripts..."

# 1. Setup Script Template
$SetupTemplate = @'
$LogPath = "{{TOOLS_DIR}}\sunvdm_log.txt"
Start-Transcript -Path $LogPath -Append
function Log-Message { param([string]$msg) Write-Host "$(Get-Date -Format 'HH:mm:ss') - $msg" }

try {
    Log-Message "--- SETUP STARTED ---"
    $ScriptPath = "{{TOOLS_DIR}}"
    $MultiTool = Join-Path $ScriptPath "MultiMonitorTool.exe"
    $ConfigBackup = Join-Path $ScriptPath "monitor_config.cfg"
    $CsvPath = Join-Path $ScriptPath "current_monitors.csv"

    # CONFIGURATION INJECTED BY INSTALLER
    $width = {{WIDTH}}; $height = {{HEIGHT}}; $fps = {{FPS}}
    Log-Message "Target: $width x $height @ $fps"

    # Backup
    Start-Process -FilePath $MultiTool -ArgumentList "/SaveConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden
    if (-not (Test-Path $ConfigBackup)) { Throw "Config backup failed." }

    # Enable VDD
    Log-Message "Enabling VDD..."
    $vdd_pnp = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" -or $_.FriendlyName -match "Virtual Display" } | Select-Object -First 1
    if (-not $vdd_pnp) { Throw "Virtual Display Driver not found." }
    $vdd_pnp | Enable-PnpDevice -Confirm:$false -ErrorAction Stop

    # Wait for Registration
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

    # Switch Primary
    Log-Message "Setting Primary: $($virtual_mon.Name)"
    Start-Process -FilePath $MultiTool -ArgumentList "/SetPrimary $($virtual_mon.Name)" -Wait -WindowStyle Hidden
    Start-Process -FilePath $MultiTool -ArgumentList "/Enable $($virtual_mon.Name)" -Wait -WindowStyle Hidden

    # Disable Physical (MST Optimized)
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

    # Resolution
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

# Inject Config Values
$FinalSetupScript = $SetupTemplate.Replace("{{WIDTH}}", $GlobalConfig.ResolutionWidth).Replace("{{HEIGHT}}", $GlobalConfig.ResolutionHeight).Replace("{{FPS}}", $GlobalConfig.RefreshRate).Replace("{{TOOLS_DIR}}", $GlobalConfig.ToolsDir)
$FinalSetupScript | Set-Content "$($GlobalConfig.ToolsDir)\setup_sunvdm.ps1" -Encoding UTF8

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

    Log-Message "Disabling VDD..."
    $vdd_pnp = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" -or $_.FriendlyName -match "Virtual Display" } | Select-Object -First 1
    if ($vdd_pnp) { $vdd_pnp | Disable-PnpDevice -Confirm:$false -ErrorAction Continue }

    Log-Message "Restoring Config..."
    if (Test-Path $ConfigBackup) {
        Start-Process -FilePath $MultiTool -ArgumentList "/LoadConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden
    }

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
$TeardownScript | Set-Content "$($GlobalConfig.ToolsDir)\teardown_sunvdm.ps1" -Encoding UTF8

# 3. AdvancedRun Configs
foreach ($key in $AppList.Keys) {
    $parts = $AppList[$key].Split("|")
    $content = "[General]`r`nExeFilename=$($parts[0])`r`nCommandLine=$($parts[1])`r`nStartDirectory=$($parts[2])`r`nRunAs=$($parts[3])`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=$($parts[4])"
    $content | Set-Content "$($GlobalConfig.ToolsDir)\$key"
}

# ---------------------------------------------------------------------------
# PHASE 4: SUNSHINE CONFIGURATION
# ---------------------------------------------------------------------------
Write-Host "Applying Sunshine Settings..."

if (Test-Path $GlobalConfig.SunshineConfig) {
    # Sunshine Config
    $confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_setup.cfg","undo":"C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_teardown.cfg"}]'
    $confContent | Set-Content "$($GlobalConfig.SunshineConfig)\sunshine.conf" -Encoding UTF8

    # Apps JSON
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
    { "name": "Restart PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_restart.cfg", "undo": "" } ], "image-path": "restart.png" },
    { "name": "YouTube TV", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_browser.cfg", "undo": "" } ], "image-path": "browser.png" }
  ]
}
'@
    $appsContent | Set-Content "$($GlobalConfig.SunshineConfig)\apps.json" -Encoding UTF8
}

# ---------------------------------------------------------------------------
# PHASE 5: ARTWORK & CLEANUP
# ---------------------------------------------------------------------------
Write-Host "Downloading Cover Art..."
$CoversDir = Join-Path $GlobalConfig.SunshineConfig "covers"
if (-not (Test-Path $CoversDir)) { New-Item -ItemType Directory -Force -Path $CoversDir | Out-Null }

foreach ($img in $CoverArt.Keys) {
    $dest = Join-Path $CoversDir $img
    if (-not (Test-Path $dest)) {
        try { Invoke-WebRequest -Uri $CoverArt[$img] -OutFile $dest } catch { Write-Warning "Skipped artwork: $img" }
    }
}

Write-Host "Unblocking Files..."
Get-ChildItem -Path $GlobalConfig.ToolsDir -Recurse | Unblock-File

Write-Host "Restarting Sunshine..."
Stop-Service "Sunshine Service" -ErrorAction SilentlyContinue
Get-Process "sunshine" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service "Sunshine Service" -ErrorAction SilentlyContinue

Write-Host ">>> INSTALLATION COMPLETE! <<<" -ForegroundColor Green
