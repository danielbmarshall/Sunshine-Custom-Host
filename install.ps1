# ============================================================================
#  SUNSHINE CUSTOM HOST - UNIFIED INSTALLER (NIRSOFT CERTIFIED SYNTAX)
#  Refined based on AdvancedRun v1.51 Documentation
# ============================================================================
$ErrorActionPreference = "Stop"
$ToolsDir = "C:\Sunshine-Tools"
$SunshineConfigDir = "C:\Program Files\Sunshine\config"
$SunshineCoversDir = "$SunshineConfigDir\covers"

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Please run this script as Administrator!"
    exit
}

# Helper to write UTF8-NoBOM (Standard for .cfg/json)
function Write-Config {
    param($Path, $Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

Write-Host ">>> STARTING NIRSOFT-OPTIMIZED DEPLOYMENT..." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. SOFTWARE INSTALLATION (Idempotent)
# ---------------------------------------------------------------------------
# Sunshine
if (-not (Get-Service "Sunshine Service" -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Sunshine..." -ForegroundColor Yellow
    winget install --id LizardByte.Sunshine -e --silent --accept-package-agreements --accept-source-agreements
    Start-Sleep -Seconds 5
}

# Playnite
if (-not (Test-Path "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe")) {
    Write-Host "Installing Playnite..." -ForegroundColor Yellow
    winget install --id Playnite.Playnite -e --silent --accept-package-agreements --accept-source-agreements
}

# Virtual Display Driver (Signed)
$vddCheck = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" }
if (-not $vddCheck) {
    Write-Host "Installing Virtual Display Driver..." -ForegroundColor Yellow
    $vddUrl = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/24.12.24/Signed-Driver-v24.12.24-x64.zip"
    $vddZip = "$env:TEMP\vdd_driver.zip"
    $vddDir = "C:\VirtualDisplayDriver"
    Invoke-WebRequest -Uri $vddUrl -OutFile $vddZip
    if (Test-Path $vddDir) { Remove-Item $vddDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $vddDir | Out-Null
    Expand-Archive -Path $vddZip -DestinationPath "$env:TEMP\vdd_extract" -Force
    Get-ChildItem -Path "$env:TEMP\vdd_extract" -Recurse -File | Copy-Item -Destination $vddDir -Force
    Write-Host "Registering Driver..."
    pnputil /add-driver "$vddDir\MttVDD.inf" /install
}

# ---------------------------------------------------------------------------
# 2. TOOL DEPLOYMENT
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
if (Test-Path "$ToolsDir\WindowsDisplayManager-master") {
    Rename-Item -Path "$ToolsDir\WindowsDisplayManager-master" -NewName "WindowsDisplayManager" -Force
}

# ---------------------------------------------------------------------------
# 3. POWERSHELL SCRIPTS (Setup/Teardown)
# ---------------------------------------------------------------------------
# Note: We use hardcoded paths inside the scripts for reliability
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
    $width = 3840; $height = 2160; $fps = 60

    # Backup
    Start-Process -FilePath $MultiTool -ArgumentList "/SaveConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden

    # Enable VDD
    Log-Message "Enabling VDD..."
    $vdd_pnp = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" } | Select-Object -First 1
    if ($vdd_pnp) { $vdd_pnp | Enable-PnpDevice -Confirm:$false -ErrorAction Stop }

    # Wait for Registration
    Log-Message "Waiting for VDD..."
    $max_retries = 20; $virtual_mon = $null
    do {
        Start-Process -FilePath $MultiTool -ArgumentList "/scomma `"$CsvPath`"" -Wait -WindowStyle Hidden
        if (Test-Path $CsvPath) {
            $monitors = Import-Csv $CsvPath
            $virtual_mon = $monitors | Where-Object { $_.'MonitorID' -match "MTT" -or $_.'Monitor Name' -match "VDD" }
        }
        if ($virtual_mon) { break }
        Start-Sleep -Milliseconds 250
    } while ($max_retries-- -gt 0)

    if ($virtual_mon) {
        # Switch Primary
        Start-Process -FilePath $MultiTool -ArgumentList "/SetPrimary $($virtual_mon.Name)" -Wait -WindowStyle Hidden
        Start-Process -FilePath $MultiTool -ArgumentList "/Enable $($virtual_mon.Name)" -Wait -WindowStyle Hidden

        # Disable Physical (MST Optimized - Hub Last)
        Log-Message "Disabling Physical..."
        Start-Process -FilePath $MultiTool -ArgumentList "/scomma `"$CsvPath`"" -Wait -WindowStyle Hidden
        $monitors = Import-Csv $CsvPath
        $sorted = $monitors | Sort-Object { if ($_.Name -eq "\\.\DISPLAY5") { 1 } else { 0 } }
        foreach ($m in $sorted) {
            if ($m.Active -eq "Yes" -and $m.Name -ne $virtual_mon.Name) {
                Start-Process -FilePath $MultiTool -ArgumentList "/disable $($m.Name)" -Wait -WindowStyle Hidden
            }
        }
        
        # Set Resolution
        Import-Module (Join-Path $ScriptPath "WindowsDisplayManager") -ErrorAction SilentlyContinue
        $displays = WindowsDisplayManager\GetAllPotentialDisplays
        $vdDisplay = $displays | Where-Object { $_.source.description -eq $vdd_pnp.FriendlyName } | Select-Object -First 1
        if ($vdDisplay) { $vdDisplay.SetResolution([int]$width, [int]$height, [int]$fps) }
    }
} catch {
    Log-Message "ERROR: $($_.Exception.Message) - ROLLING BACK"
    Start-Process -FilePath $MultiTool -ArgumentList "/LoadConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden
}
Stop-Transcript
'@
Write-Config "$ToolsDir\setup_sunvdm.ps1" $SetupScript

$TeardownScript = @'
$LogPath = "C:\Sunshine-Tools\sunvdm_log.txt"
Start-Transcript -Path $LogPath -Append
function Log-Message { param([string]$msg) Write-Host "$(Get-Date -Format 'HH:mm:ss') - $msg" }
try {
    Log-Message "--- TEARDOWN STARTED ---"
    $ScriptPath = "C:\Sunshine-Tools"
    $MultiTool = Join-Path $ScriptPath "MultiMonitorTool.exe"
    $ConfigBackup = Join-Path $ScriptPath "monitor_config.cfg"

    # Disable VDD
    $vdd_pnp = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" } | Select-Object -First 1
    if ($vdd_pnp) { $vdd_pnp | Disable-PnpDevice -Confirm:$false -ErrorAction Continue }

    # Restore Physical
    if (Test-Path $ConfigBackup) {
        Start-Process -FilePath $MultiTool -ArgumentList "/LoadConfig `"$ConfigBackup`"" -Wait -WindowStyle Hidden
    }
    # Enforce Hub Primary
    Start-Process -FilePath $MultiTool -ArgumentList "/SetPrimary \\.\DISPLAY5" -Wait -WindowStyle Hidden
    Start-Process -FilePath $MultiTool -ArgumentList "/Enable \\.\DISPLAY5" -Wait -WindowStyle Hidden
} catch {
    Log-Message "ERROR: $($_.Exception.Message)"
    & $MultiTool /Enable \\.\DISPLAY5
    & $MultiTool /SetPrimary \\.\DISPLAY5
}
Stop-Transcript
'@
Write-Config "$ToolsDir\teardown_sunvdm.ps1" $TeardownScript

# ---------------------------------------------------------------------------
# 4. ADVANCEDRUN CONFIGS (.CFG) - DOCUMENTATION COMPLIANT
# ---------------------------------------------------------------------------
# RunAs Mapping based on NirSoft PDF:
# 1 = Current User (Allow UAC)
# 2 = Current User (No UAC)
# 3 = Administrator (Force UAC)
# 4 = SYSTEM

# WaitProcess=1 ensures Sunshine waits for the script to finish (Preventing Race Condition) 
# ParseVarInsideCmdLine=1 ensures %LOCALAPPDATA% works 

$Configs = @{
    # Monitor Scripts: RunAs=3 (Admin), WaitProcess=1 (Wait for completion)
    "cfg_setup.cfg"    = "[General]`r`nExeFilename=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`r`nCommandLine=-ExecutionPolicy Bypass -File `"C:\Sunshine-Tools\setup_sunvdm.ps1`"`r`nStartDirectory=C:\Sunshine-Tools`r`nRunAs=3`r`nWaitProcess=1`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
    "cfg_teardown.cfg" = "[General]`r`nExeFilename=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`r`nCommandLine=-ExecutionPolicy Bypass -File `"C:\Sunshine-Tools\teardown_sunvdm.ps1`"`r`nStartDirectory=C:\Sunshine-Tools`r`nRunAs=3`r`nWaitProcess=1`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
    
    # Apps: RunAs=1 (User), WaitProcess=0 (Don't wait, let Sunshine detach), ParseVar=1
    "cfg_steam.cfg"    = "[General]`r`nExeFilename=C:\Windows\explorer.exe`r`nCommandLine=steam://open/bigpicture`r`nStartDirectory=C:\Windows`r`nRunAs=1`r`nWaitProcess=0`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
    "cfg_xbox.cfg"     = "[General]`r`nExeFilename=C:\Windows\explorer.exe`r`nCommandLine=shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App`r`nStartDirectory=C:\Windows`r`nRunAs=1`r`nWaitProcess=0`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
    "cfg_playnite.cfg" = "[General]`r`nExeFilename=%LOCALAPPDATA%\Playnite\Playnite.FullscreenApp.exe`r`nStartDirectory=%LOCALAPPDATA%\Playnite`r`nRunAs=1`r`nWaitProcess=0`r`nParseVarInsideCmdLine=1`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=3"
    "cfg_esde.cfg"     = "[General]`r`nExeFilename=%APPDATA%\EmuDeck\Emulators\ES-DE\ES-DE.exe`r`nStartDirectory=%APPDATA%\EmuDeck\Emulators\ES-DE`r`nRunAs=1`r`nWaitProcess=0`r`nParseVarInsideCmdLine=1`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=3"
    "cfg_browser.cfg"  = "[General]`r`nExeFilename=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`r`nCommandLine=--kiosk https://www.youtube.com/tv --edge-kiosk-type=fullscreen`r`nStartDirectory=C:\Program Files (x86)\Microsoft\Edge\Application`r`nRunAs=1`r`nWaitProcess=0`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=3"
    
    # Utilities: RunAs=3 (Admin)
    "cfg_sleep.cfg"    = "[General]`r`nExeFilename=C:\Windows\System32\rundll32.exe`r`nCommandLine=powrprof.dll,SetSuspendState 0,1,0`r`nStartDirectory=C:\Windows\System32`r`nRunAs=3`r`nWaitProcess=0`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
    "cfg_restart.cfg"  = "[General]`r`nExeFilename=C:\Windows\System32\shutdown.exe`r`nCommandLine=/r /t 0`r`nStartDirectory=C:\Windows\System32`r`nRunAs=3`r`nWaitProcess=0`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nWindowState=0"
    "cfg_taskmgr.cfg"  = "[General]`r`nExeFilename=C:\Windows\System32\Taskmgr.exe`r`nStartDirectory=C:\Windows\System32`r`nRunAs=3`r`nWaitProcess=0`r`nRunAsProcessMode=1`r`nPriorityClass=5`r`nWindowState=1"
}

foreach ($key in $Configs.Keys) {
    Write-Config "$ToolsDir\$key" $Configs[$key]
    # Create Batch Wrapper (Nuclear option for parser safety)
    $batContent = "@echo off`r`n`"C:\Sunshine-Tools\AdvancedRun.exe`" /Run `"$ToolsDir\$key`""
    Write-Config "$ToolsDir\launch_$key.bat" $batContent
}

# ---------------------------------------------------------------------------
# 5. DOWNLOAD ARTWORK (Browser UserAgent)
# ---------------------------------------------------------------------------
Write-Host "Downloading App Cover Art..."
if (-not (Test-Path $SunshineCoversDir)) { New-Item -ItemType Directory -Force -Path $SunshineCoversDir | Out-Null }

$Covers = @{
    "steam.png"    = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Steam_icon_logo.svg/512px-Steam_icon_logo.svg.png"
    "playnite.png" = "https://raw.githubusercontent.com/JosefNemec/Playnite/master/source/Playnite/Resources/Images/AppIcon.png"
    "xbox.png"     = "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/Xbox_one_logo.svg/512px-Xbox_one_logo.svg.png"
    "esde.png"     = "https://gitlab.com/es-de/emulationstation-de/-/raw/master/resources/logo.png"
    "taskmgr.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Task_Manager_icon_%28Windows%29.svg/512px-Task_Manager_icon_%28Windows%29.svg.png"
    "sleep.png"    = "https://upload.wikimedia.org/wikipedia/commons/thumb/2/21/Oxygen480-actions-system-suspend.svg/512px-Oxygen480-actions-system-suspend.svg.png"
    "restart.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4c/Gnome-system-restart.svg/512px-Gnome-system-restart.svg.png"
    "browser.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Google_Chrome_icon_%28September_2014%29.svg/512px-Google_Chrome_icon_%28September_2014%29.svg.png"
    "desktop.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Windows_11_logo.svg/512px-Windows_11_logo.svg.png"
}

foreach ($img in $Covers.Keys) {
    $dest = "$SunshineCoversDir\$img"
    try {
        Invoke-WebRequest -Uri $Covers[$img] -OutFile $dest -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        Write-Host " + Downloaded $img"
    } catch { Write-Warning "Failed to download $img" }
}

# ---------------------------------------------------------------------------
# 6. DEPLOY SUNSHINE CONFIGS
# ---------------------------------------------------------------------------
Write-Host "Updating Sunshine Configuration..."

if (Test-Path $SunshineConfigDir) {
    # Pointing to BATCH wrappers to ensure Sunshine parser sees 0 arguments
    $confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\launch_setup.bat","undo":"C:\\Sunshine-Tools\\launch_teardown.bat"}]'
    Write-Config "$SunshineConfigDir\sunshine.conf" $confContent

    $appsContent = @'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png" },
    { "name": "Steam Big Picture", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_steam.bat", "undo": "" } ], "image-path": "steam.png" },
    { "name": "Xbox (Game Pass)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_xbox.bat", "undo": "" } ], "image-path": "xbox.png" },
    { "name": "Playnite", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_playnite.bat", "undo": "" } ], "image-path": "playnite.png" },
    { "name": "EmulationStation", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_esde.bat", "undo": "" } ], "image-path": "esde.png" },
    { "name": "YouTube TV", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_browser.bat", "undo": "" } ], "image-path": "browser.png" },
    { "name": "Task Manager (Rescue)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_taskmgr.bat", "undo": "" } ], "image-path": "taskmgr.png" },
    { "name": "Sleep PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_sleep.bat", "undo": "" } ], "image-path": "sleep.png" },
    { "name": "Restart PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_restart.bat", "undo": "" } ], "image-path": "restart.png" }
  ]
}
'@
    Write-Config "$SunshineConfigDir\apps.json" $appsContent
}

# ---------------------------------------------------------------------------
# 7. RESTART SERVICE
# ---------------------------------------------------------------------------
Write-Host "Unblocking files..."
Get-ChildItem -Path $ToolsDir -Recurse | Unblock-File

Write-Host "Restarting Sunshine..."
Stop-Service "Sunshine Service" -ErrorAction SilentlyContinue
Get-Process "sunshine" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service "Sunshine Service" -ErrorAction SilentlyContinue

Write-Host ">>> COMPLETE! Your Custom Sunshine Host is Ready. <<<" -ForegroundColor Green
