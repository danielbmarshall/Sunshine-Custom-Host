# ==============================================================================
# SUNSHINE CUSTOM HOST - INSTALLER (NO NULL PATHS, TESTED PATTERNS)
# ==============================================================================

$ErrorActionPreference = 'Stop'

# --- Global Paths / Config ----------------------------------------------------
$ToolsDir          = 'C:\Sunshine-Tools'
$SunshineConfigDir = 'C:\Program Files\Sunshine\config'
$SunshineCoversDir = "$SunshineConfigDir\covers"

# Resolution for the virtual display (VDD)
$MonitorConfig = @{
    Width   = 3840
    Height  = 2160
    Refresh = 60
}

# App definitions: Exe|CommandLine|StartDir|RunAs|WindowState|WaitProcess
#   RunAs:
#     1 = Current user
#     3 = Run as Administrator
#   WindowState:
#     0 = Hidden, 1 = Normal, 3 = Maximized
#   WaitProcess:
#     0 = Don't wait, 1 = Wait for process exit
$Apps = @{
    'setup'    = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$ToolsDir\setup_sunvdm.ps1`"|$ToolsDir|3|0|1"
    'teardown' = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$ToolsDir\teardown_sunvdm.ps1`"|$ToolsDir|3|0|1"
    'steam'    = "C:\Windows\explorer.exe|steam://open/bigpicture|C:\Windows|1|0|0"
    'xbox'     = "C:\Windows\explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\Windows|1|0|0"
    # playnite will be added later once $playniteExe is discovered
    'esde'     = "$env:APPDATA\EmuDeck\Emulators\ES-DE\ES-DE.exe||$env:APPDATA\EmuDeck\Emulators\ES-DE|1|3|0"
    'sleep'    = "C:\Windows\System32\rundll32.exe|powrprof.dll,SetSuspendState 0,1,0|C:\Windows\System32|3|0|0"
    'restart'  = "C:\Windows\System32\shutdown.exe|/r /t 0|C:\Windows\System32|3|0|0"
    'taskmgr'  = "C:\Windows\System32\Taskmgr.exe||C:\Windows\System32|3|1|0"
    'browser'  = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe|--profile-directory=Default --start-fullscreen|C:\Program Files (x86)\Microsoft\Edge\Application|1|3|0"
}

# Cover art URLs per logical app
$Covers = @{
    'steam.png'    = 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Steam_icon_logo.svg/512px-Steam_icon_logo.svg.png'
    'playnite.png' = 'https://playnite.link/applogo.png'
    'xbox.png'     = 'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/Xbox_one_logo.svg/512px-Xbox_one_logo.svg.png'
    'esde.png'     = 'https://gitlab.com/uploads/-/system/project/avatar/18817634/emulationstation_1024x1024.png'
    'taskmgr.png'  = 'https://upload.wikimedia.org/wikipedia/commons/a/ac/Windows_11_TASKMGR.png'
    'sleep.png'    = 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0f/Oxygen480-actions-system-suspend.svg/480px-Oxygen480-actions-system-suspend.svg.png'
    'restart.png'  = 'https://www.svgrepo.com/png/378038/gnome-session-reboot.png'
    'browser.png'  = 'https://upload.wikimedia.org/wikipedia/commons/8/87/Google_Chrome_icon_%282011%29.png'
    'desktop.png'  = 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Windows_11_logo.svg/512px-Windows_11_logo.svg.png'
}

# --- Helper: UTF8 (no BOM) writer --------------------------------------------
function Write-Config {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Content
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "Updated: $(Split-Path $Path -Leaf)" -ForegroundColor Gray
}

function Install-WingetApp {
    param(
        [Parameter(Mandatory)] [string] $Id
    )
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget.exe not found. Please install '$Id' manually."
        return
    }

    Write-Host "Installing $Id via winget..." -ForegroundColor Yellow
    winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements
}

# ---------------------------------------------------------------------------
# 1. PREP: CREATE TOOLS FOLDER
# ---------------------------------------------------------------------------

Write-Host "Preparing tools directory at '$ToolsDir'..." -ForegroundColor Cyan
if (-not (Test-Path $ToolsDir)) {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
}

# ---------------------------------------------------------------------------
# 2. INSTALL CORE SOFTWARE (SUNSHINE, PLAYNITE, VDD)
# ---------------------------------------------------------------------------

Write-Host 'Checking for Sunshine...' -ForegroundColor Cyan
if (-not (Get-Service 'SunshineService' -ErrorAction SilentlyContinue)) {
    Install-WingetApp -Id 'LizardByte.Sunshine'
} else {
    Write-Host 'Sunshine already installed.' -ForegroundColor Green
}

Write-Host 'Checking for Playnite...' -ForegroundColor Cyan
$playniteExe = @(
    'C:\Program Files\Playnite\Playnite.FullscreenApp.exe',
    'C:\Program Files (x86)\Playnite\Playnite.FullscreenApp.exe',
    "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $playniteExe) {
    Install-WingetApp -Id 'Playnite.Playnite'
    $playniteExe = @(
        'C:\Program Files\Playnite\Playnite.FullscreenApp.exe',
        'C:\Program Files (x86)\Playnite\Playnite.FullscreenApp.exe',
        "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($playniteExe) {
    Write-Host "Playnite found at: $playniteExe" -ForegroundColor Green
    # SAFE: Only add Playnite to $Apps once we know the path is NOT null
    $Apps['playnite'] = "$playniteExe||$(Split-Path -Path $playniteExe)|1|3|0"
} else {
    Write-Warning 'Playnite executable not found even after install. Playnite tile will be skipped.'
}

# Virtual Display Driver (VDD) install if not present
Write-Host 'Checking for Virtual Display Driver (VDD)...' -ForegroundColor Cyan
$vddPresent = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Idd' -or $_.FriendlyName -match 'MTT' } |
    Select-Object -First 1

if (-not $vddPresent) {
    Write-Host 'Installing VDD...' -ForegroundColor Yellow
    $vddUrl  = 'https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/24.12.24/Signed-Driver-v24.12.24-x64.zip'
    $vddZip  = Join-Path $env:TEMP 'vdd.zip'
    $vddDir  = 'C:\VirtualDisplayDriver'
    $vddTemp = Join-Path $env:TEMP 'vdd_extract'

    Invoke-WebRequest -Uri $vddUrl -OutFile $vddZip -UseBasicParsing

    if (Test-Path $vddDir)  { Remove-Item $vddDir  -Recurse -Force }
    if (Test-Path $vddTemp) { Remove-Item $vddTemp -Recurse -Force }

    New-Item -ItemType Directory -Force -Path $vddDir  | Out-Null
    New-Item -ItemType Directory -Force -Path $vddTemp | Out-Null

    Expand-Archive -Path $vddZip -DestinationPath $vddTemp -Force
    Get-ChildItem -Path $vddTemp -Recurse -File | Copy-Item -Destination $vddDir -Force
    pnputil /add-driver "$vddDir\MttVDD.inf" /install
} else {
    Write-Host "Virtual Display Driver already present: $($vddPresent.FriendlyName)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. DOWNLOAD ADVANCEDRUN + VDM SCRIPTS INTO C:\Sunshine-Tools
# ---------------------------------------------------------------------------

Write-Host 'Downloading AdvancedRun...' -ForegroundColor Cyan
$advancedRunUrl  = 'https://www.nirsoft.net/utils/advancedrun-x64.zip'
$advancedRunZip  = Join-Path $env:TEMP 'advancedrun.zip'
$advancedRunTemp = Join-Path $env:TEMP 'advancedrun_extract'

Invoke-WebRequest -Uri $advancedRunUrl -OutFile $advancedRunZip -UseBasicParsing

if (Test-Path $advancedRunTemp) {
    Remove-Item $advancedRunTemp -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $advancedRunTemp | Out-Null

Expand-Archive -Path $advancedRunZip -DestinationPath $advancedRunTemp -Force
Copy-Item -Path (Join-Path $advancedRunTemp 'AdvancedRun.exe') -Destination (Join-Path $ToolsDir 'AdvancedRun.exe') -Force

# --- Setup / Teardown scripts for virtual monitor (VDM) ----------------------
$setupScript = @'
param(
    [int] $Width   = 3840,
    [int] $Height  = 2160,
    [int] $Refresh = 60
)

$ErrorActionPreference = "Stop"

$LogPath    = "C:\Sunshine-Tools\sunvdm.log"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "$timestamp [SETUP] $Message"
}

Write-Log "--- SETUP STARTED ---"

try {
    $multiTool     = Join-Path $ScriptPath "MultiMonitorTool.exe"
    $configBackup  = Join-Path $ScriptPath "monitor_config.cfg"
    $csvPath       = Join-Path $ScriptPath "current_monitors.csv"

    if (-not (Test-Path $multiTool)) {
        Write-Log "ERROR: MultiMonitorTool.exe not found."
        throw "MultiMonitorTool.exe missing from $ScriptPath"
    }

    & $multiTool /smonitors $csvPath
    Write-Log "Exported monitor list to $csvPath"

    $monitors = Import-Csv $csvPath
    $virtual  = $monitors | Where-Object {
        $_.'Monitor Name' -match 'MTT' -or $_.'Monitor Name' -match 'Idd'
    } | Select-Object -First 1

    if (-not $virtual) {
        Write-Log "No virtual monitor present, attempting to enable one..."
        & $multiTool /turnon 2
        Start-Sleep -Seconds 2
        & $multiTool /smonitors $csvPath
        $monitors = Import-Csv $csvPath
        $virtual  = $monitors | Where-Object {
            $_.'Monitor Name' -match 'MTT' -or $_.'Monitor Name' -match 'Idd'
        } | Select-Object -First 1
    }

    if (-not $virtual) {
        Write-Log "ERROR: Could not find virtual monitor after enabling."
        throw "Virtual monitor not found"
    }

    Write-Log "Virtual monitor detected: $($virtual.'Monitor Name') / $($virtual.'Monitor ID')"

    # Backup config once
    if (-not (Test-Path $configBackup)) {
        & $multiTool /sconfig $configBackup
        Write-Log "Saved original monitor config to $configBackup"
    }

    # Apply custom resolution and make it primary
    & $multiTool /setprimary $($virtual.'Monitor ID')
    & $multiTool /SetMonitors $($virtual.'Monitor ID') "$Width" "$Height" "$Refresh" 32
    Write-Log "Applied virtual monitor resolution ${Width}x${Height}@${Refresh}"

    Write-Log "--- SETUP COMPLETED SUCCESSFULLY ---"
}
catch {
    Write-Log "EXCEPTION: $($_.Exception.Message)"
    throw
}
'@

$teardownScript = @'
$ErrorActionPreference = "Stop"

$LogPath    = "C:\Sunshine-Tools\sunvdm.log"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "$timestamp [TEARDOWN] $Message"
}

Write-Log "--- TEARDOWN STARTED ---"

try {
    $multiTool    = Join-Path $ScriptPath "MultiMonitorTool.exe"
    $configBackup = Join-Path $ScriptPath "monitor_config.cfg"

    if (-not (Test-Path $multiTool)) {
        Write-Log "ERROR: MultiMonitorTool.exe not found."
        throw "MultiMonitorTool.exe missing from $ScriptPath"
    }

    if (Test-Path $configBackup) {
        & $multiTool /loadconfig $configBackup
        Write-Log "Restored original monitor configuration from $configBackup"
    }
    else {
        Write-Log "Backup config not found; skipping restore."
    }

    Write-Log "--- TEARDOWN COMPLETED SUCCESSFULLY ---"
}
catch {
    Write-Log "EXCEPTION: $($_.Exception.Message)"
    throw
}
'@

Write-Config (Join-Path $ToolsDir 'setup_sunvdm.ps1')    $setupScript
Write-Config (Join-Path $ToolsDir 'teardown_sunvdm.ps1') $teardownScript

# Download MultiMonitorTool (portable)
Write-Host 'Downloading MultiMonitorTool...' -ForegroundColor Cyan
$mmUrl  = 'https://www.nirsoft.net/utils/multimonitortool-x64.zip'
$mmZip  = Join-Path $env:TEMP 'multimonitortool.zip'
$mmTemp = Join-Path $env:TEMP 'multimonitortool_extract'

Invoke-WebRequest -Uri $mmUrl -OutFile $mmZip -UseBasicParsing

if (Test-Path $mmTemp) {
    Remove-Item $mmTemp -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $mmTemp | Out-Null

Expand-Archive -Path $mmZip -DestinationPath $mmTemp -Force
Copy-Item -Path (Join-Path $mmTemp 'MultiMonitorTool.exe') -Destination (Join-Path $ToolsDir 'MultiMonitorTool.exe') -Force

# ---------------------------------------------------------------------------
# 4. GENERATE ADVANCEDRUN CFG FILES (DEBUGGING ONLY)
# ---------------------------------------------------------------------------

Write-Host 'Generating AdvancedRun config files...' -ForegroundColor Cyan

foreach ($key in $Apps.Keys) {
    $parts = $Apps[$key].Split('|')
    if ($parts.Count -lt 6) {
        Write-Warning "Skipping app '$key' due to malformed definition."
        continue
    }

    $cfgName = "cfg_$key.cfg"
    $cfgPath = Join-Path $ToolsDir $cfgName

    $cfgContent = "[General]`r`n" +
                  "ExeFilename=$($parts[0])`r`n" +
                  "CommandLine=$($parts[1])`r`n" +
                  "StartDirectory=$($parts[2])`r`n" +
                  "RunAs=$($parts[3])`r`n" +
                  "WindowState=$($parts[4])`r`n" +
                  "WaitProcess=$($parts[5])`r`n" +
                  "RunAsProcessMode=1`r`n" +
                  "PriorityClass=3`r`n" +
                  "ParseVarInsideCmdLine=1`r`n" +
                  "AutoRun=1"

    Write-Config $cfgPath $cfgContent
}

# ---------------------------------------------------------------------------
# 5. DOWNLOAD COVER ART
# ---------------------------------------------------------------------------

Write-Host 'Downloading App Cover Art...' -ForegroundColor Cyan

if (-not (Test-Path $SunshineCoversDir)) {
    New-Item -ItemType Directory -Force -Path $SunshineCoversDir | Out-Null
}

foreach ($img in $Covers.Keys) {
    $dest = "$SunshineCoversDir\$img"
    if (-not (Test-Path $dest)) {
        try {
            Invoke-WebRequest -Uri $Covers[$img] -OutFile $dest -UseBasicParsing
            Write-Host "Downloaded cover: $img" -ForegroundColor DarkGray
        }
        catch {
            Write-Warning "Failed to download cover '$img': $($_.Exception.Message)"
        }
    } else {
        Write-Host "Cover already exists: $img" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 6. UPDATE SUNSHINE CONFIG (sunshine.conf + apps.json)
# ---------------------------------------------------------------------------

if (Test-Path $SunshineConfigDir) {
    Write-Host "Configuring Sunshine in '$SunshineConfigDir'..." -ForegroundColor Cyan

    # Backup any existing configs
    $configFiles = @('sunshine.conf', 'apps.json')
    foreach ($file in $configFiles) {
        $path = Join-Path $SunshineConfigDir $file
        if (Test-Path $path -and -not (Test-Path "$path.bak")) {
            Copy-Item $path "$path.bak" -Force
            Write-Host "Backed up $file to $file.bak" -ForegroundColor DarkGray
        }
    }

    # global_prep_cmd: call the PowerShell setup/teardown scripts directly (no BAT/VBS), run elevated
    $confContent = @'
global_prep_cmd = [{
  "do":"powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\Sunshine-Tools\\setup_sunvdm.ps1\"",
  "undo":"powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\Sunshine-Tools\\teardown_sunvdm.ps1\"",
  "elevated":true
}]
'@
    Write-Config "$SunshineConfigDir\sunshine.conf" $confContent

    # Build apps.json dynamically from the $Apps table and emit canonical JSON
    $appsJson = [ordered]@{
        env  = @{}
        apps = @()
    }

    # Desktop entry (no prep-cmd, just a cover)
    $appsJson.apps += [ordered]@{
        name         = 'Desktop'
        'image-path' = "C:\Program Files\Sunshine\config\covers\desktop.png"
    }

    # Map logical keys -> display names and cover files
    $appDisplay = @{
        steam   = 'Steam Big Picture'
        xbox    = 'Xbox (Game Pass)'
        playnite= 'Playnite'
        esde    = 'EmulationStation'
        browser = 'YouTube TV'
        taskmgr = 'Task Manager (Rescue)'
        sleep   = 'Sleep PC'
        restart = 'Restart PC'
    }

    $coverMap = @{
        steam   = 'steam.png'
        xbox    = 'xbox.png'
        playnite= 'playnite.png'
        esde    = 'esde.png'
        browser = 'browser.png'
        taskmgr = 'taskmgr.png'
        sleep   = 'sleep.png'
        restart = 'restart.png'
    }

    foreach ($key in $appDisplay.Keys) {
        if (-not $Apps.ContainsKey($key)) {
            # e.g., playnite missing -> skip cleanly
            continue
        }

        $parts = $Apps[$key].Split('|')
        if ($parts.Count -lt 6) {
            Write-Warning "Skipping app '$key' in apps.json due to malformed definition."
            continue
        }

        $exe       = $parts[0]
        $cmdLine   = $parts[1]
        $startDir  = $parts[2]
        $runAs     = $parts[3]
        $window    = $parts[4]
        $waitProc  = $parts[5]

        # Escape any embedded quotes to keep JSON + CLI stable
        $safeExe      = $exe.Replace('"','\"')
        $safeCmdLine  = $cmdLine.Replace('"','\"')
        $safeStartDir = $startDir.Replace('"','\"')

        # This is the pattern we manually validated:
        # AdvancedRun.exe /EXEFilename "<exe>" /CommandLine "<args>" /StartDirectory "<dir>" /RunAs <n> /Run
        $do = "C:\\Sunshine-Tools\\AdvancedRun.exe /EXEFilename `"$safeExe`""

        if ($safeCmdLine -ne '') {
            $do += " /CommandLine `"$safeCmdLine`""
        }

        if ($safeStartDir -ne '') {
            $do += " /StartDirectory `"$safeStartDir`""
        }

        if ($runAs -ne '')    { $do += " /RunAs $runAs" }
        if ($window -ne '')   { $do += " /WindowState $window" }
        if ($waitProc -ne '') { $do += " /WaitProcess $waitProc" }

        $do += " /Run"

        $appsJson.apps += [ordered]@{
            name         = $appDisplay[$key]
            'prep-cmd'   = @(@{
                do   = $do
                undo = ''
            })
            'image-path' = "C:\Program Files\Sunshine\config\covers\$($coverMap[$key])"
        }
    }

    $appsContent = $appsJson | ConvertTo-Json -Depth 6
    Write-Config "$SunshineConfigDir\apps.json" $appsContent
}
else {
    Write-Warning "Sunshine config directory '$SunshineConfigDir' not found. Skipping Sunshine config update."
}

# ---------------------------------------------------------------------------
# 7. FINAL CLEANUP & RESTART
# ---------------------------------------------------------------------------

Write-Host 'Unblocking files...' -ForegroundColor Cyan
Get-ChildItem -Path $ToolsDir -Recurse -ErrorAction SilentlyContinue |
    Unblock-File -ErrorAction SilentlyContinue

Write-Host 'Restarting Sunshine...' -ForegroundColor Cyan
Stop-Service 'SunshineService' -ErrorAction SilentlyContinue
Get-Process 'sunshine' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service 'SunshineService' -ErrorAction SilentlyContinue

Write-Host '>>> COMPLETE! Your Custom Sunshine Host is Ready. <<<' -ForegroundColor Green
