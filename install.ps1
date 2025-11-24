# ============================================================================
#  SUNSHINE CUSTOM HOST - UNIFIED INSTALLER (v3.0)
#  - Architecture: Config Block + Dynamic Injection
#  - Reliability: AdvancedRun + NoBOM + Browser Headers
# ============================================================================

# --- [USER CONFIGURATION BLOCK] ---------------------------------------------
# EDIT THESE VALUES TO CUSTOMIZE YOUR INSTALLATION
# ----------------------------------------------------------------------------
$GlobalConfig = @{
    # Target Display Settings
    Width  = "3840"
    Height = "2160"
    FPS    = "60"

    # Directories
    ToolsDir       = "C:\Sunshine-Tools"
    SunshineConfig = "C:\Program Files\Sunshine\config"
}
# ----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"
$SunshineCoversDir = "$($GlobalConfig.SunshineConfig)\covers"

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Please run this script as Administrator!"
    exit
}

# Helper: Write UTF8-NoBOM (Crucial for Sunshine Parser)
function Write-Config {
    param($Path, $Content)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "Updated: $(Split-Path $Path -Leaf)" -ForegroundColor Gray
}

Write-Host ">>> STARTING CONFIGURABLE DEPLOYMENT..." -ForegroundColor Cyan
Write-Host "Target Resolution: $($GlobalConfig.Width)x$($GlobalConfig.Height) @ $($GlobalConfig.FPS)Hz" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. PREPARE ENVIRONMENT
# ---------------------------------------------------------------------------
if (-not (Test-Path $GlobalConfig.ToolsDir)) { New-Item -ItemType Directory -Force -Path $GlobalConfig.ToolsDir | Out-Null }

# Grant Everyone Full Control (Fixes 'Access Denied' edge cases)
$acl = Get-Acl $GlobalConfig.ToolsDir
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","FullControl","ContainerInherit,ObjectInherit","None","Allow")
$acl.SetAccessRule($rule)
Set-Acl $GlobalConfig.ToolsDir $acl

# ---------------------------------------------------------------------------
# 2. INSTALL SOFTWARE (Idempotent Checks)
# ---------------------------------------------------------------------------
if (-not (Get-Service "Sunshine Service" -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Sunshine..." -ForegroundColor Yellow
    winget install --id LizardByte.Sunshine -e --silent --accept-package-agreements --accept-source-agreements
    Start-Sleep -Seconds 5
}

if (-not (Test-Path "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe")) {
    Write-Host "Installing Playnite..." -ForegroundColor Yellow
    winget install --id Playnite.Playnite -e --silent --accept-package-agreements --accept-source-agreements
}

# Virtual Display Driver (Signed)
$vddCheck = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" }
if (-not $vddCheck) {
    Write-Host "Installing VDD..." -ForegroundColor Yellow
    $vddUrl = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/24.12.24/Signed-Driver-v24.12.24-x64.zip"
    $vddZip = "$env:TEMP\vdd.zip"
    $vddDir = "C:\VirtualDisplayDriver"
    
    Invoke-WebRequest -Uri $vddUrl -OutFile $vddZip
    if (Test-Path $vddDir) { Remove-Item $vddDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $vddDir | Out-Null
    Expand-Archive -Path $vddZip -DestinationPath "$env:TEMP\vdd_extract" -Force
    Get-ChildItem -Path "$env:TEMP\vdd_extract" -Recurse -File | Copy-Item -Destination $vddDir -Force
    
    pnputil /add-driver "$vddDir\MttVDD.inf" /install
}

# ---------------------------------------------------------------------------
# 3. DEPLOY TOOLS (NirSoft + WDM)
# ---------------------------------------------------------------------------
$Downloads = @(
    @{ Name="MultiMonitorTool"; Url="https://www.nirsoft.net/utils/multimonitortool-x64.zip" },
    @{ Name="AdvancedRun";      Url="https://www.nirsoft.net/utils/advancedrun-x64.zip" },
    @{ Name="WinDisplayMgr";    Url="https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip" }
)

foreach ($tool in $Downloads) {
    $zipPath = "$($GlobalConfig.ToolsDir)\$($tool.Name).zip"
    # Download if missing to speed up re-runs
    if (-not (Test-Path "$($GlobalConfig.ToolsDir)\$($tool.Name).exe") -and -not (Test-Path "$($GlobalConfig.ToolsDir)\WindowsDisplayManager")) {
        Write-Host "Downloading $($tool.Name)..."
        Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $GlobalConfig.ToolsDir -Force
        Remove-Item $zipPath -Force
    }
}
if (Test-Path "$($GlobalConfig.ToolsDir)\WindowsDisplayManager-master") {
    Rename-Item -Path "$($GlobalConfig.ToolsDir)\WindowsDisplayManager-master" -NewName "WindowsDisplayManager" -Force
}

# ---------------------------------------------------------------------------
# 4. GENERATE POWERSHELL SCRIPTS (With Variable Injection)
# ---------------------------------------------------------------------------
Write-Host "Generating Hardened Scripts..."

# Setup Script Template
$SetupTemplate = @'
$LogPath = "{{TOOLS}}\sunvdm_log.txt"
Start-Transcript -Path $LogPath -Append
function Log-Message { param([string]$msg) Write-Host "$(Get-Date -Format 'HH:mm:ss') - $msg" }

try {
    Log-Message "--- SETUP STARTED ---"
    $ScriptPath = "{{TOOLS}}"
    $MultiTool = Join-Path $ScriptPath "MultiMonitorTool.exe"
    $ConfigBackup = Join-Path $ScriptPath "monitor_config.cfg"
    $CsvPath = Join-Path $ScriptPath "current_monitors.csv"

    # INJECTED CONFIGURATION
    $width = {{WIDTH}}; $height = {{HEIGHT}}; $fps = {{FPS}}
    Log-Message "Target: $width x $height @ $fps"

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

# Inject Variables
$FinalSetup = $SetupTemplate.Replace("{{WIDTH}}", $GlobalConfig.Width).Replace("{{HEIGHT}}", $GlobalConfig.Height).Replace("{{FPS}}", $GlobalConfig.FPS).Replace("{{TOOLS}}", $GlobalConfig.ToolsDir)
Write-Config "$($GlobalConfig.ToolsDir)\setup_sunvdm.ps1" $FinalSetup

# Teardown Script (No injection needed, but using variable for ToolsDir)
$TeardownTemplate = @'
$LogPath = "{{TOOLS}}\sunvdm_log.txt"
Start-Transcript -Path $LogPath -Append
function Log-Message { param([string]$msg) Write-Host "$(Get-Date -Format 'HH:mm:ss') - $msg" }
try {
    Log-Message "--- TEARDOWN STARTED ---"
    $ScriptPath = "{{TOOLS}}"
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
$FinalTeardown = $TeardownTemplate.Replace("{{TOOLS}}", $GlobalConfig.ToolsDir)
Write-Config "$($GlobalConfig.ToolsDir)\teardown_sunvdm.ps1" $FinalTeardown


# ---------------------------------------------------------------------------
# 5. ADVANCEDRUN CONFIGS + BATCH WRAPPERS
# ---------------------------------------------------------------------------
# RunAs Mapping: 1=User(AllowUAC), 3=Admin(ForceUAC). 
# WindowState: 0=Hidden, 3=Max. 
# WaitProcess: 1=Yes(Scripts), 0=No(Apps).

$Apps = @{
    "setup"    = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$($GlobalConfig.ToolsDir)\setup_sunvdm.ps1`"|$($GlobalConfig.ToolsDir)|3|0|1"
    "teardown" = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$($GlobalConfig.ToolsDir)\teardown_sunvdm.ps1`"|$($GlobalConfig.ToolsDir)|3|0|1"
    "steam"    = "C:\Windows\explorer.exe|steam://open/bigpicture|C:\Windows|1|0|0"
    "xbox"     = "C:\Windows\explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\Windows|1|0|0"
    "playnite" = "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe||$env:LOCALAPPDATA\Playnite|1|3|0"
    "esde"     = "$env:APPDATA\EmuDeck\Emulators\ES-DE\ES-DE.exe||$env:APPDATA\EmuDeck\Emulators\ES-DE|1|3|0"
    "sleep"    = "C:\Windows\System32\rundll32.exe|powrprof.dll,SetSuspendState 0,1,0|C:\Windows\System32|3|0|0"
    "restart"  = "C:\Windows\System32\shutdown.exe|/r /t 0|C:\Windows\System32|3|0|0"
    "taskmgr"  = "C:\Windows\System32\Taskmgr.exe||C:\Windows\System32|3|1|0"
    "browser"  = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe|--kiosk https://www.youtube.com/tv --edge-kiosk-type=fullscreen|C:\Program Files (x86)\Microsoft\Edge\Application|1|3|0"
}

foreach ($key in $Apps.Keys) {
    $parts = $Apps[$key].Split("|")
    $cfgContent = "[General]`r`nExeFilename=$($parts[0])`r`nCommandLine=$($parts[1])`r`nStartDirectory=$($parts[2])`r`nRunAs=$($parts[3])`r`nWindowState=$($parts[4])`r`nWaitProcess=$($parts[5])`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nParseVarInsideCmdLine=1"
    Write-Config "$($GlobalConfig.ToolsDir)\cfg_$key.cfg" $cfgContent
    
    # Batch Wrapper (Zero-Argument Trigger for Sunshine)
    $batContent = "@echo off`r`n`"$($GlobalConfig.ToolsDir)\AdvancedRun.exe`" /Run `"$($GlobalConfig.ToolsDir)\cfg_$key.cfg`""
    Write-Config "$($GlobalConfig.ToolsDir)\launch_$key.bat" $batContent
}

# ---------------------------------------------------------------------------
# 6. DEPLOY SUNSHINE CONFIGS
# ---------------------------------------------------------------------------
Write-Host "Updating Sunshine..."
if (Test-Path $GlobalConfig.SunshineConfig) {
    $confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\launch_setup.bat","undo":"C:\\Sunshine-Tools\\launch_teardown.bat"}]'
    Write-Config "$($GlobalConfig.SunshineConfig)\sunshine.conf" $confContent

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
    Write-Config "$($GlobalConfig.SunshineConfig)\apps.json" $appsContent
}

# ---------------------------------------------------------------------------
# 7. DOWNLOAD ARTWORK (Browser Headers)
# ---------------------------------------------------------------------------
Write-Host "Downloading Artwork..."
if (-not (Test-Path $SunshineCoversDir)) { New-Item -ItemType Directory -Force -Path $SunshineCoversDir | Out-Null }

$Covers = @{
    "steam.png"    = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Steam_icon_logo.svg/512px-Steam_icon_logo.svg.png"
    "playnite.png" = "https://playnite.link/applogo.png"
    "xbox.png"     = "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/Xbox_one_logo.svg/512px-Xbox_one_logo.svg.png"
    "esde.png"     = "https://gitlab.com/uploads/-/system/project/avatar/18817634/emulationstation_1024x1024.png"
    "taskmgr.png"  = "https://upload.wikimedia.org/wikipedia/commons/a/ac/Windows_11_TASKMGR.png"
    "sleep.png"    = "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Oxygen480-actions-system-suspend.svg/480px-Oxygen480-actions-system-suspend.svg.png"
    "restart.png"  = "https://icons.iconarchive.com/icons/oxygen-icons.org/oxygen/128/Actions-system-reboot-icon.png"
    "browser.png"  = "https://upload.wikimedia.org/wikipedia/commons/8/87/Google_Chrome_icon_%282011%29.png"
    "desktop.png"  = "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Windows_11_logo.svg/512px-Windows_11_logo.svg.png"
}

foreach ($img in $Covers.Keys) {
    $dest = "$SunshineCoversDir\$img"
    try {
        Invoke-WebRequest -Uri $Covers[$img] -OutFile $dest -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        Write-Host " + Downloaded $img"
    } catch { Write-Warning "Skipped $img" }
}

# ---------------------------------------------------------------------------
# 8. CLEANUP & RESTART
# ---------------------------------------------------------------------------
Write-Host "Restarting Sunshine..."
Get-ChildItem -Path $GlobalConfig.ToolsDir -Recurse | Unblock-File
Stop-Service "Sunshine Service" -ErrorAction SilentlyContinue
Get-Process "sunshine" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service "Sunshine Service" -ErrorAction SilentlyContinue

Write-Host ">>> INSTALLATION COMPLETE! <<<" -ForegroundColor Green
