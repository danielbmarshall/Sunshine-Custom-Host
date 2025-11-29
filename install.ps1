# ==============================================================================
# SUNSHINE CUSTOM HOST - MENU INSTALLER
# - Installs / repairs Sunshine
# - Installs / repairs Sunshine-Tools (AdvancedRun, MultiMonitorTool)
# - Sets up VDM (virtual display) scripts
# - Generates sunshine.conf (global_prep_cmd)
# - Generates apps.json (Steam, Xbox, Playnite, ES-DE, etc.)
# ==============================================================================

param(
    [switch]$NoMenu  # If you want fully non-interactive full setup later, you can use this
)

$ErrorActionPreference = 'Stop'

# --- Global Paths / Config ----------------------------------------------------
$ToolsDir          = 'C:\Sunshine-Tools'
$SunshineConfigDir = 'C:\Program Files\Sunshine\config'
$SunshineCoversDir = "$SunshineConfigDir\covers"

# Virtual Display / monitor layout config for VDM scripts
# Adjust these IDs if needed (they match what you just tested)
# Example here: GTX1050 outputs = 1,2; RTX3070 outputs = 3,5,6; Virtual = 7
$VirtualMonitorId   = '7'
$PhysicalMonitorIds = @('1','2','3','5','6')

# App definitions: Exe|CommandLine|StartDir|RunAs|WindowState|WaitProcess
#   RunAs:        1 = Current user, 3 = Run as Administrator
#   WindowState:  0 = Hidden, 1 = Normal, 3 = Maximized
#   WaitProcess:  0 = Don't wait, 1 = Wait for process exit
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

# --- Helpers ------------------------------------------------------------------

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
        [Parameter(Mandatory)] [string] $Id,
        [string]$DisplayName = $Id,
        [switch]$Force,
        [string]$Override
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget.exe not found. Please install '$DisplayName' manually."
        return
    }

    $args = @(
        'install',
        '--id', $Id,
        '-e',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    if ($Force) {
        $args += '--force'
    }

    if ($Override) {
        $args += '--override'
        $args += $Override
    }

    Write-Host "Installing or repairing $DisplayName via winget..." -ForegroundColor Yellow

    try {
        winget @args
    }
    catch {
        # If --force is unsupported, retry without it
        if ($Force -and $_.Exception.Message -like '*--force*') {
            Write-Warning "winget does not support --force on this system; retrying without it..."
            $args = $args | Where-Object { $_ -ne '--force' }
            winget @args
        }
        else {
            throw
        }
    }
}

function Stop-ProcessesIfRunning {
    param(
        [Parameter(Mandatory)][string[]] $Names
    )

    foreach ($name in $Names) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $procs) {
            continue
        }

        Write-Host "Stopping running instance(s) of $name..." -ForegroundColor Yellow

        foreach ($proc in $procs) {
            try {
                if ($proc.HasExited) {
                    continue
                }

                if ($proc.MainWindowHandle -ne 0) {
                    $null = $proc.CloseMainWindow()
                    if (-not $proc.WaitForExit(4000)) {
                        $proc.Kill()
                    }
                }
                else {
                    $proc.Kill()
                }
            }
            catch {
                Write-Warning "Unable to stop $name (PID $($proc.Id)): $($_.Exception.Message)"
            }
        }

        Start-Sleep -Milliseconds 300
    }
}

# --- Core actions -------------------------------------------------------------

function Install-Sunshine {
    param(
        [switch]$Force
    )

    Write-Host "=== Install / Repair Sunshine ===" -ForegroundColor Cyan

    # Avoid terminating on clean machines where the service does not exist
    try {
        $svc = Get-Service 'SunshineService' -ErrorAction Stop
    }
    catch {
        $svc = $null
    }

    if (-not $Force) {
        if ($svc) {
            Write-Host "Sunshine service detected (status: $($svc.Status)). Skipping install (use Force to reinstall)." -ForegroundColor Green
            return
        }
    }

    # Always force winget install so it reinstalls even when the same version is detected
    # Pass quiet installer overrides to suppress UI (avoid prompts like "Sunshine is already installed")
    $sunshineOverrides = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCANCEL'
    Install-WingetApp -Id 'LizardByte.Sunshine' -DisplayName 'Sunshine' -Force:$true -Override $sunshineOverrides
}

function Install-Tools {
    param(
        [switch]$Force
    )

    Write-Host "=== Install / Repair Sunshine-Tools ===" -ForegroundColor Cyan

    if (-not (Test-Path $ToolsDir)) {
        Write-Host "Creating tools directory at '$ToolsDir'..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    }

    $advancedRunExe = Join-Path $ToolsDir 'AdvancedRun.exe'
    if ((Test-Path $advancedRunExe) -and -not $Force) {
        Write-Host "AdvancedRun already installed. Skipping download (use Force to reinstall)." -ForegroundColor Green
    }
    else {
        Write-Host 'Downloading AdvancedRun...' -ForegroundColor Cyan
        Stop-ProcessesIfRunning -Names @('AdvancedRun')
        $advancedRunUrl  = 'https://www.nirsoft.net/utils/advancedrun-x64.zip'
        $advancedRunZip  = Join-Path $env:TEMP 'advancedrun.zip'
        $advancedRunTemp = Join-Path $env:TEMP 'advancedrun_extract'

        Invoke-WebRequest -Uri $advancedRunUrl -OutFile $advancedRunZip -UseBasicParsing

        if (Test-Path $advancedRunTemp) {
            Remove-Item $advancedRunTemp -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $advancedRunTemp | Out-Null

        Expand-Archive -Path $advancedRunZip -DestinationPath $advancedRunTemp -Force
        Copy-Item -Path (Join-Path $advancedRunTemp 'AdvancedRun.exe') -Destination $advancedRunExe -Force -ErrorAction Stop
    }

    $mmExe = Join-Path $ToolsDir 'MultiMonitorTool.exe'
    if ((Test-Path $mmExe) -and -not $Force) {
        Write-Host "MultiMonitorTool already installed. Skipping download (use Force to reinstall)." -ForegroundColor Green
    }
    else {
        Write-Host 'Downloading MultiMonitorTool...' -ForegroundColor Cyan
        Stop-ProcessesIfRunning -Names @('MultiMonitorTool')
        $mmUrl  = 'https://www.nirsoft.net/utils/multimonitortool-x64.zip'
        $mmZip  = Join-Path $env:TEMP 'multimonitortool.zip'
        $mmTemp = Join-Path $env:TEMP 'multimonitortool_extract'

        Invoke-WebRequest -Uri $mmUrl -OutFile $mmZip -UseBasicParsing

        if (Test-Path $mmTemp) {
            Remove-Item $mmTemp -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $mmTemp | Out-Null

        Expand-Archive -Path $mmZip -DestinationPath $mmTemp -Force
        Copy-Item -Path (Join-Path $mmTemp 'MultiMonitorTool.exe') -Destination $mmExe -Force -ErrorAction Stop
    }

    $ahExe   = Join-Path $ToolsDir 'AutoHideMouseCursor.exe'
    $startup = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'

    if ((Test-Path $ahExe) -and -not $Force) {
        Write-Host "AutoHideMouseCursor already installed. Skipping download (use Force to reinstall)." -ForegroundColor Green
    }
    else {
        Write-Host 'Downloading AutoHideMouseCursor...' -ForegroundColor Cyan
        $ahUrl  = 'https://www.softwareok.com/Download/AutoHideMouseCursor.zip'
        $ahZip  = Join-Path $env:TEMP 'autohidemousecursor.zip'
        $ahTemp = Join-Path $env:TEMP 'autohidemousecursor_extract'

        Invoke-WebRequest -Uri $ahUrl -OutFile $ahZip -UseBasicParsing

        if (Test-Path $ahTemp) {
            Remove-Item $ahTemp -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $ahTemp | Out-Null

        Expand-Archive -Path $ahZip -DestinationPath $ahTemp -Force
        $ahSource = Get-ChildItem -Path $ahTemp -Filter 'AutoHideMouseCursor.exe' -Recurse | Select-Object -First 1
        if ($ahSource) {
            $copied     = $false
            $maxRetries = 2

            while (-not $copied -and $maxRetries -ge 0) {
                # Stop running instance so copy will not fail
                Get-Process -Name 'AutoHideMouseCursor' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300

                try {
                    Copy-Item -Path $ahSource.FullName -Destination $ahExe -Force -ErrorAction Stop
                    $copied = $true
                }
                catch {
                    $maxRetries--
                    $msg = $_.Exception.Message

                    if ($maxRetries -lt 0) {
                        Write-Warning "Failed to update AutoHideMouseCursor.exe after multiple attempts: $msg"
                        Write-Host "Please exit AutoHideMouseCursor from the system tray, then rerun 'Install / Repair Sunshine-Tools' from the menu to finish the update." -ForegroundColor Yellow
                        break
                    }

                    Write-Warning "AutoHideMouseCursor.exe is still running or locked: $msg"
                    $input = Read-Host "Close AutoHideMouseCursor manually (tray icon) then press Enter to retry, or type 'S' to skip updating it"
                    if ($input -match '^(s|skip)$') {
                        Write-Warning "Skipping AutoHideMouseCursor update per user request. You can rerun Install / Repair Sunshine-Tools later."
                        break
                    }
                }
            }
        }
        else {
            Write-Warning 'AutoHideMouseCursor.exe not found in extracted archive.'
        }
    }

    if (-not (Test-Path $startup)) {
        New-Item -ItemType Directory -Force -Path $startup | Out-Null
    }
    $shortcutPath = Join-Path $startup 'AutoHideMouseCursor.lnk'
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $ahExe
        $shortcut.WorkingDirectory = $ToolsDir
        $shortcut.Save()
    }
    catch {
        Write-Warning "Failed to create startup shortcut for AutoHideMouseCursor: $($_.Exception.Message)"
    }

    Write-Host "Tools installed under $ToolsDir." -ForegroundColor Green
}

function Setup-VDMScripts {
    Write-Host "=== Generating VDM scripts (setup/teardown) ===" -ForegroundColor Cyan

    $physicalList = ($PhysicalMonitorIds -join '","')

    $setupTemplate = @'
param(
    [int] $ClientWidth,
    [int] $ClientHeight,
    [int] $ClientFps,
    [int] $ClientHdr
)

# =========================
# CONFIG - ADJUST IF NEEDED
# =========================

$MultiToolPath       = "C:\Sunshine-Tools\MultiMonitorTool.exe"
$LogPath             = "C:\Sunshine-Tools\sunvdm.log"
$NormalLayoutConfig  = "C:\Sunshine-Tools\monitor_config.cfg"

# IDs from installer config
$VirtualMonitorId    = "{VIRTUAL_MONITOR}"
$PhysicalMonitorIds  = @("{PHYSICAL_MONITORS}")
$SetVirtualToMax     = $true

# =========================
# END CONFIG
# =========================

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "$timestamp [SETUP] $Message"
}

function Invoke-MMTool {
    param(
        [Parameter(Mandatory)] [string[]] $Args,
        [string] $Step
    )
    Write-Log "Running: ""$MultiToolPath $($Args -join ' ')"""
    try {
        & $MultiToolPath @Args
        Write-Log "Step '$Step' exit code: $($LASTEXITCODE)"
    }
    catch {
        Write-Log "Step '$Step' failed: $($_.Exception.Message)"
        throw
    }
}

Write-Log "=== Sunshine VDM SETUP started ==="
Write-Log "Args: width=$ClientWidth height=$ClientHeight fps=$ClientFps hdr=$ClientHdr"
Write-Log "Config: VMon=$VirtualMonitorId Physical=[$($PhysicalMonitorIds -join ',')] SetVirtualToMax=$SetVirtualToMax"

if (-not (Test-Path $MultiToolPath)) {
    Write-Log "ERROR: MultiMonitorTool.exe not found at '$MultiToolPath'. Skipping VDM setup."
    exit 1
}

if (-not (Test-Path $NormalLayoutConfig)) {
    Write-Log "Saving current monitor configuration to '$NormalLayoutConfig'..."
    Invoke-MMTool -Args @('/SaveConfig', "$NormalLayoutConfig") -Step "SaveConfig"
} else {
    Write-Log "Normal layout config already exists at '$NormalLayoutConfig'; skipping save."
}

Invoke-MMTool -Args @('/enable', $VirtualMonitorId) -Step "EnableVirtual"

foreach ($monId in $PhysicalMonitorIds) {
    Invoke-MMTool -Args @('/disable', $monId) -Step "DisablePhysical-$monId"
}

Invoke-MMTool -Args @('/SetPrimary', $VirtualMonitorId) -Step "SetPrimary"

# Apply client-requested resolution if provided; otherwise set max
if ($ClientWidth -gt 0 -and $ClientHeight -gt 0) {
    $fps = if ($ClientFps -gt 0) { $ClientFps } else { 60 }
    Write-Log "Setting virtual monitor resolution to ${ClientWidth}x${ClientHeight}@${fps}"
    Invoke-MMTool -Args @('/SetMonRes', $VirtualMonitorId, "$ClientWidth", "$ClientHeight", '32', "$fps") -Step "SetResolution"
} elseif ($SetVirtualToMax) {
    Invoke-MMTool -Args @('/SetMax', $VirtualMonitorId) -Step "SetMax"
}

Write-Log "=== Sunshine VDM SETUP complete ==="
exit 0
'@
    $setupScript = $setupTemplate.Replace('{VIRTUAL_MONITOR}', $VirtualMonitorId).Replace('{PHYSICAL_MONITORS}', $physicalList)

    $teardownScript = @'
# =========================
# CONFIG - ADJUST IF NEEDED
# =========================

$MultiToolPath      = "C:\Sunshine-Tools\MultiMonitorTool.exe"
$LogPath            = "C:\Sunshine-Tools\sunvdm.log"
$NormalLayoutConfig = "C:\Sunshine-Tools\monitor_config.cfg"

# =========================
# END CONFIG
# =========================

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "$timestamp [TEARDOWN] $Message"
}

function Invoke-MMTool {
    param(
        [Parameter(Mandatory)] [string[]] $Args,
        [string] $Step
    )
    Write-Log "Running: ""$MultiToolPath $($Args -join ' ')"""
    try {
        & $MultiToolPath @Args
        Write-Log "Step '$Step' exit code: $($LASTEXITCODE)"
    }
    catch {
        Write-Log "Step '$Step' failed: $($_.Exception.Message)"
        throw
    }
}

Write-Log "=== Sunshine VDM TEARDOWN started ==="

if (-not (Test-Path $MultiToolPath)) {
    Write-Log "ERROR: MultiMonitorTool.exe not found at '$MultiToolPath'. Cannot restore layout."
    exit 0
}

if (-not (Test-Path $NormalLayoutConfig)) {
    Write-Log "WARNING: Normal layout config '$NormalLayoutConfig' not found. Nothing to restore."
    exit 0
}

try {
    Write-Log "Restoring normal monitor configuration from '$NormalLayoutConfig'..."
    Invoke-MMTool -Args @('/LoadConfig', "$NormalLayoutConfig") -Step "LoadConfig"
    Write-Log "Normal layout restore attempted."
}
catch {
    Write-Log "WARNING: Failed to restore monitor layout: $($_.Exception.Message)"
}

# Ensure physical monitors are enabled again and virtual disabled
foreach ($monId in $PhysicalMonitorIds) {
    try { Invoke-MMTool -Args @('/enable', $monId) -Step "ReEnable-$monId" } catch { Write-Log "WARN: re-enable $monId failed: $($_.Exception.Message)" }
}
try { Invoke-MMTool -Args @('/disable', $VirtualMonitorId) -Step "DisableVirtual" } catch { Write-Log "WARN: disable virtual failed: $($_.Exception.Message)" }

Write-Log "=== Sunshine VDM TEARDOWN complete ==="
exit 0
'@

    Write-Config (Join-Path $ToolsDir 'setup_sunvdm.ps1')    $setupScript
    Write-Config (Join-Path $ToolsDir 'teardown_sunvdm.ps1') $teardownScript
}

function Configure-AppsAndConfig {
    Write-Host "=== Configure Sunshine (conf + apps + covers) ===" -ForegroundColor Cyan

    # Re-detect Playnite (so menu can repair it if paths change)
    Write-Host 'Checking for Playnite...' -ForegroundColor Cyan
    $playniteExe = @(
        'C:\Program Files\Playnite\Playnite.FullscreenApp.exe',
        'C:\Program Files (x86)\Playnite\Playnite.FullscreenApp.exe',
        "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($playniteExe) {
        Write-Host "Playnite found at: $playniteExe" -ForegroundColor Green
        $Apps['playnite'] = "$playniteExe||$(Split-Path -Path $playniteExe)|1|3|0"
    }
    else {
        if ($Apps.ContainsKey('playnite')) {
            $Apps.Remove('playnite') | Out-Null
        }
        Write-Warning 'Playnite executable not found. Playnite tile will be skipped.'
    }

    # Covers
    if (-not (Test-Path $SunshineCoversDir)) {
        New-Item -ItemType Directory -Force -Path $SunshineCoversDir | Out-Null
    }

    Write-Host 'Downloading App Cover Art...' -ForegroundColor Cyan
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
        }
        else {
            Write-Host "Cover already exists: $img" -ForegroundColor DarkGray
        }
    }

    if (Test-Path $SunshineConfigDir) {
        # Backup configs once
        $configFiles = @('sunshine.conf', 'apps.json')
        foreach ($file in $configFiles) {
            $path = Join-Path $SunshineConfigDir $file
            if (Test-Path $path) {
                if (-not (Test-Path "$path.bak")) {
                    Copy-Item $path "$path.bak" -Force
                    Write-Host "Backed up $file to $file.bak" -ForegroundColor DarkGray
                }
            }
        }

        # sunshine.conf
        $confContent = @"
global_prep_cmd = [{
  "do":"powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\Sunshine-Tools\\setup_sunvdm.ps1\"",
  "undo":"powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\Sunshine-Tools\\teardown_sunvdm.ps1\"",
  "elevated":true
}]
"@
        Write-Config "$SunshineConfigDir\sunshine.conf" $confContent

        # apps.json
        $appsJson = [ordered]@{
            env  = @{}
            apps = @()
        }

        # Desktop (no prep)
        $appsJson.apps += [ordered]@{
            name         = 'Desktop'
            'image-path' = "C:\Program Files\Sunshine\config\covers\desktop.png"
        }

        $appDisplay = @{
            steam    = 'Steam Big Picture'
            xbox     = 'Xbox (Game Pass)'
            playnite = 'Playnite'
            esde     = 'EmulationStation'
            browser  = 'YouTube TV'
            taskmgr  = 'Task Manager (Rescue)'
            sleep    = 'Sleep PC'
            restart  = 'Restart PC'
        }

        $coverMap = @{
            steam    = 'steam.png'
            xbox     = 'xbox.png'
            playnite = 'playnite.png'
            esde     = 'esde.png'
            browser  = 'browser.png'
            taskmgr  = 'taskmgr.png'
            sleep    = 'sleep.png'
            restart  = 'restart.png'
        }

        foreach ($key in $appDisplay.Keys) {
            if (-not $Apps.ContainsKey($key)) { continue }

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

            $safeExe      = $exe.Replace('"','\"')
            $safeCmdLine  = $cmdLine.Replace('"','\"')
            $safeStartDir = $startDir.Replace('"','\"')

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
}

function Ensure-VDD {
    Write-Host '=== Check / Install Virtual Display Driver (VDD) ===' -ForegroundColor Cyan

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
    }
    else {
        Write-Host "Virtual Display Driver already present: $($vddPresent.FriendlyName)" -ForegroundColor Green
    }
}

function Restart-Sunshine {
    Write-Host 'Restarting Sunshine service...' -ForegroundColor Cyan
    Stop-Service 'SunshineService' -ErrorAction SilentlyContinue
    Get-Process 'sunshine' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Service 'SunshineService' -ErrorAction SilentlyContinue
}

function Full-Setup {
    Install-Sunshine
    Ensure-VDD
    Install-Tools
    Setup-VDMScripts
    Configure-AppsAndConfig

    Write-Host 'Unblocking tools folder...' -ForegroundColor Cyan
    Get-ChildItem -Path $ToolsDir -Recurse -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue

    Restart-Sunshine

    Write-Host '>>> COMPLETE! Your Custom Sunshine Host is Ready. <<<' -ForegroundColor Green
}

function Nuclear-ReinstallSunshine {
    Write-Host "=== NUCLEAR REINSTALL: Sunshine + Sunshine-Tools ===" -ForegroundColor Red
    Write-Host "This will:" -ForegroundColor Red
    Write-Host "  - Stop and uninstall Sunshine" -ForegroundColor Red
    Write-Host "  - Delete C:\Program Files\Sunshine" -ForegroundColor Red
    Write-Host "  - Delete $ToolsDir" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "Type 'NUKE' in ALL CAPS to continue, or anything else to cancel"

    if ($confirm -ne 'NUKE') {
        Write-Host "Nuclear reinstall cancelled." -ForegroundColor Yellow
        return
    }

    Write-Host "Stopping Sunshine service and processes..." -ForegroundColor Cyan
    Stop-Service 'SunshineService' -ErrorAction SilentlyContinue
    Get-Process 'sunshine' -ErrorAction SilentlyContinue | Stop-Process -Force

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Uninstalling Sunshine via winget..." -ForegroundColor Cyan
        try {
            # Newer winget builds reject accept-* flags; use force/purge to ensure removal
            winget uninstall --id LizardByte.Sunshine -e --silent --force --purge
        }
        catch {
            Write-Warning "winget uninstall failed: $($_.Exception.Message). You may need to uninstall Sunshine manually via Apps & Features."
        }
    }
    else {
        Write-Warning "winget not available; skipping automated uninstall."
    }

    Write-Host "Removing Sunshine program folder..." -ForegroundColor Cyan
    Remove-Item 'C:\Program Files\Sunshine' -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Removing Sunshine-Tools folder..." -ForegroundColor Cyan
    Remove-Item $ToolsDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Fresh install of Sunshine..." -ForegroundColor Cyan
    Install-Sunshine -Force

    Write-Host "Reinstalling tools, VDM scripts, and configs..." -ForegroundColor Cyan
    Install-Tools -Force
    Setup-VDMScripts
    Configure-AppsAndConfig
    Restart-Sunshine

    Write-Host ">>> Nuclear reinstall complete. <<<<" -ForegroundColor Green
}

# --- Menu ---------------------------------------------------------------------

function Show-MainMenu {
    while ($true) {
        Write-Host ""
        Write-Host "================ Sunshine Custom Host Installer ================" -ForegroundColor Cyan
        Write-Host "0) Full setup (recommended)" -ForegroundColor Yellow
        Write-Host "1) Install / Repair Sunshine"
        Write-Host "2) Install / Repair Sunshine-Tools (AdvancedRun, MultiMonitorTool)"
        Write-Host "3) Configure VDM scripts (setup/teardown)"
        Write-Host "4) Configure Sunshine (sunshine.conf + apps.json + covers)"
        Write-Host "5) Check / Install Virtual Display Driver (VDD)"
        Write-Host "6) Restart Sunshine Service"
        Write-Host "7) Nuclear reinstall Sunshine + Sunshine-Tools (UNINSTALL + DELETE FOLDERS + REINSTALL)" -ForegroundColor Red
        Write-Host "Q) Quit"
        Write-Host "================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select an option (default 0)"

        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '0' }

        switch ($choice.ToUpperInvariant()) {
            '0' { Full-Setup }
            '1' {
                $force = Read-Host "Force reinstall via winget even if Sunshine service exists? (y/N)"
                if ($force -match '^(y|yes)$') {
                    Install-Sunshine -Force
                } else {
                    Install-Sunshine
                }
            }
            '2' {
                $forceTools = Read-Host "Force reinstall of Sunshine-Tools even if files already exist? (y/N)"
                if ($forceTools -match '^(y|yes)$') {
                    Install-Tools -Force
                }
                else {
                    Install-Tools
                }
            }
            '3' { Setup-VDMScripts }
            '4' { Configure-AppsAndConfig }
            '5' { Ensure-VDD }
            '6' { Restart-Sunshine }
            '7' { Nuclear-ReinstallSunshine }
            'Q' { Write-Host "Exiting installer." -ForegroundColor Green; break }
            default { Write-Host "Invalid selection. Try again." -ForegroundColor Red }
        }
    }
}

# --- Entry point -------------------------------------------------------------

if ($NoMenu) {
    Full-Setup
}
else {
    Show-MainMenu
}
