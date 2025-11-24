# ==============================================================================
# SUNSHINE CUSTOM HOST - UNIFIED INSTALLER (FIXED & HARDENED)
# ==============================================================================

$ErrorActionPreference = 'Stop'

# --- Global Paths / Config ----------------------------------------------------
$ToolsDir           = 'C:\Sunshine-Tools'
$SunshineConfigDir  = 'C:\Program Files\Sunshine\config'
$SunshineCoversDir  = "$SunshineConfigDir\covers"

# Resolution for the virtual display (VDD)
$MonitorConfig = @{
    Width   = 3840
    Height  = 2160
    Refresh = 60
}

# Cover art URLs
$Covers = @{
    'steam.png'    = 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Steam_icon_logo.svg/512px-Steam_icon_logo.svg.png'
    'playnite.png' = 'https://playnite.link/applogo.png'
    'xbox.png'     = 'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/Xbox_one_logo.svg/512px-Xbox_one_logo.svg.png'
    'esde.png'     = 'https://gitlab.com/uploads/-/system/project/avatar/18817634/emulationstation_1024x1024.png'
    'taskmgr.png'  = 'https://upload.wikimedia.org/wikipedia/commons/a/ac/Windows_11_TASKMGR.png'
    'sleep.png'    = 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Oxygen480-actions-system-suspend.svg/480px-Oxygen480-actions-system-suspend.svg.png'
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

# --- Admin check --------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Please run this script from an elevated PowerShell session.'
    exit 1
}

Write-Host '>>> STARTING UNIFIED DEPLOYMENT...' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. PREPARE ENVIRONMENT
# ---------------------------------------------------------------------------
if (-not (Test-Path $ToolsDir)) {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
}

# Grant Everyone Full Control (you can tighten this later if desired)
$acl  = Get-Acl $ToolsDir
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'Everyone','FullControl','ContainerInherit,ObjectInherit','None','Allow'
)
$acl.SetAccessRule($rule)
Set-Acl -Path $ToolsDir -AclObject $acl

# ---------------------------------------------------------------------------
# 2. INSTALL CORE SOFTWARE (SUNSHINE, PLAYNITE, VDD)
# ---------------------------------------------------------------------------

Write-Host 'Checking for Sunshine...' -ForegroundColor Cyan
if (-not (Get-Service 'Sunshine Service' -ErrorAction SilentlyContinue)) {
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
} else {
    Write-Host "Playnite already installed at: $playniteExe" -ForegroundColor Green
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

    if (Test-Path $vddDir) {
        Remove-Item $vddDir -Recurse -Force
    }
    if (Test-Path $vddTemp) {
        Remove-Item $vddTemp -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $vddDir  | Out-Null
    New-Item -ItemType Directory -Force -Path $vddTemp | Out-Null

    Expand-Archive -Path $vddZip -DestinationPath $vddTemp -Force
    Get-ChildItem -Path $vddTemp -Recurse -File | Copy-Item -Destination $vddDir -Force
    pnputil /add-driver "$vddDir\MttVDD.inf" /install
} else {
    Write-Host "VDD already present: $($vddPresent.FriendlyName)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. TOOLCHAIN (MultiMonitorTool, AdvancedRun, WindowsDisplayManager)
# ---------------------------------------------------------------------------
Write-Host 'Ensuring helper tools are in place...' -ForegroundColor Cyan

$Downloads = @(
    @{ Name = 'MultiMonitorTool'; Url = 'https://www.nirsoft.net/utils/multimonitortool-x64.zip' },
    @{ Name = 'AdvancedRun';      Url = 'https://www.nirsoft.net/utils/advancedrun-x64.zip' },
    @{ Name = 'WindowsDisplayManager'; Url = 'https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip' }
)

foreach ($tool in $Downloads) {
    $zipPath = Join-Path $ToolsDir ("{0}.zip" -f $tool.Name)

    if ($tool.Name -eq 'WindowsDisplayManager') {
        if (-not (Test-Path "$ToolsDir\WindowsDisplayManager")) {
            Write-Host 'Downloading WindowsDisplayManager...' -ForegroundColor Yellow
            Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
            Remove-Item $zipPath -Force
            if (Test-Path "$ToolsDir\WindowsDisplayManager-master") {
                Rename-Item -Path "$ToolsDir\WindowsDisplayManager-master" -NewName 'WindowsDisplayManager' -Force
            }
        }
    } else {
        $exeTest = Join-Path $ToolsDir ("{0}.exe" -f $tool.Name)
        if (-not (Test-Path $exeTest)) {
            Write-Host "Downloading $($tool.Name)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
            Remove-Item $zipPath -Force
        }
    }
}

# ---------------------------------------------------------------------------
# 4. GENERATE SETUP / TEARDOWN SCRIPTS
# ---------------------------------------------------------------------------
Write-Host 'Generating setup/teardown scripts...' -ForegroundColor Cyan

$setupScript = @"
`$ErrorActionPreference = 'Stop'

`$LogPath    = Join-Path '$ToolsDir' 'sunvdm_log.txt'
`$ScriptPath = '$ToolsDir'
`$Width      = $($MonitorConfig.Width)
`$Height     = $($MonitorConfig.Height)
`$Refresh    = $($MonitorConfig.Refresh)

function Write-Log {
    param([string]`$Message)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path `$LogPath -Value "`$timestamp [SETUP] `$Message"
}

Write-Log '--- SETUP STARTED ---'

try {
    `$multiTool     = Join-Path `$ScriptPath 'MultiMonitorTool.exe'
    `$configBackup  = Join-Path `$ScriptPath 'monitor_config.cfg'
    `$csvPath       = Join-Path `$ScriptPath 'current_monitors.csv'
    `$maxTries      = 20
    `$virtual       = `$null

    if (-not (Test-Path `$multiTool)) {
        Write-Log 'MultiMonitorTool.exe not found.'
        return
    }

    # Backup current display config
    Write-Log 'Saving current monitor configuration...'
    Start-Process -FilePath `$multiTool -ArgumentList "/SaveConfig ``"`$configBackup```"" -Wait -WindowStyle Hidden

    # Ensure VDD device is enabled
    Write-Log 'Enabling VDD display device...'
    `$vdd = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { `$_.FriendlyName -match 'Idd' -or `$_.FriendlyName -match 'MTT' } |
        Select-Object -First 1

    if (`$vdd) {
        `$vdd | Enable-PnpDevice -Confirm:\$false -ErrorAction SilentlyContinue
    } else {
        Write-Log 'No VDD device found; aborting setup.'
        return
    }

    # Poll for virtual monitor enumeration
    for (`$i = 0; `$i -lt `$maxTries -and -not `$virtual; `$i++) {
        Start-Process -FilePath `$multiTool -ArgumentList "/scomma ``"`$csvPath```"" -Wait -WindowStyle Hidden
        if (Test-Path `$csvPath) {
            `$monitors = Import-Csv `$csvPath
            `$virtual  = `$monitors | Where-Object { `$_.'Monitor Name' -match 'VDD' -or `$_.'MonitorID' -match 'MTT' } | Select-Object -First 1
        }
        if (-not `$virtual) {
            Start-Sleep -Milliseconds 250
        }
    }

    if (-not `$virtual) {
        Write-Log 'Virtual display did not appear; rolling back.'
        if (Test-Path `$configBackup) {
            Start-Process -FilePath `$multiTool -ArgumentList "/LoadConfig ``"`$configBackup```"" -Wait -WindowStyle Hidden
        }
        return
    }

    Write-Log "Virtual display found: `$(`$virtual.Name)"

    # Set VDD as primary and disable other displays
    Start-Process -FilePath `$multiTool -ArgumentList "/SetPrimary `$(`$virtual.Name)" -Wait -WindowStyle Hidden
    Start-Process -FilePath `$multiTool -ArgumentList "/Enable `$(`$virtual.Name)" -Wait -WindowStyle Hidden

    Start-Process -FilePath `$multiTool -ArgumentList "/scomma ``"`$csvPath```"" -Wait -WindowStyle Hidden
    `$monitors = Import-Csv `$csvPath
    foreach (`$m in `$monitors) {
        if (`$m.Active -eq 'Yes' -and `$m.Name -ne `$virtual.Name) {
            Write-Log "Disabling physical monitor: `$(`$m.Name)"
            Start-Process -FilePath `$multiTool -ArgumentList "/disable `$(`$m.Name)" -Wait -WindowStyle Hidden
        }
    }

    # Use WindowsDisplayManager to set resolution / refresh
    Import-Module (Join-Path `$ScriptPath 'WindowsDisplayManager') -ErrorAction SilentlyContinue
    if (Get-Command -Name 'WindowsDisplayManager\GetAllPotentialDisplays' -ErrorAction SilentlyContinue) {
        `$displays = WindowsDisplayManager\GetAllPotentialDisplays
        `$vdDisplay = `$displays | Where-Object { `$_.source.description -eq `$vdd.FriendlyName } | Select-Object -First 1
        if (`$vdDisplay) {
            Write-Log "Setting VDD resolution to `$Width x `$Height @ `$Refresh Hz"
            `$vdDisplay.SetResolution([int]`$Width, [int]`$Height, [int]`$Refresh)
        } else {
            Write-Log 'WindowsDisplayManager: VDD display entry not found.'
        }
    } else {
        Write-Log 'WindowsDisplayManager module not available.'
    }
}
catch {
    Write-Log "ERROR: `$(`$_.Exception.Message)"
}
"@

Write-Config "$ToolsDir\setup_sunvdm.ps1" $setupScript

$teardownScript = @"
`$ErrorActionPreference = 'Stop'

`$LogPath    = Join-Path '$ToolsDir' 'sunvdm_log.txt'
`$ScriptPath = '$ToolsDir'

function Write-Log {
    param([string]`$Message)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path `$LogPath -Value "`$timestamp [TEARDOWN] `$Message"
}

Write-Log '--- TEARDOWN STARTED ---'

try {
    `$multiTool    = Join-Path `$ScriptPath 'MultiMonitorTool.exe'
    `$configBackup = Join-Path `$ScriptPath 'monitor_config.cfg'

    `$vdd = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { `$_.FriendlyName -match 'Idd' -or `$_.FriendlyName -match 'MTT' } |
        Select-Object -First 1

    if (`$vdd) {
        Write-Log "Disabling VDD device: `$(`$vdd.FriendlyName)"
        `$vdd | Disable-PnpDevice -Confirm:\$false -ErrorAction SilentlyContinue
    }

    if (Test-Path `$multiTool -and Test-Path `$configBackup) {
        Write-Log 'Restoring previous monitor configuration...'
        Start-Process -FilePath `$multiTool -ArgumentList "/LoadConfig ``"`$configBackup```"" -Wait -WindowStyle Hidden
    } else {
        Write-Log 'Backup configuration not found; attempting to enable DISPLAY1 as primary.'
        if (Test-Path `$multiTool) {
            & `$multiTool /Enable \\.\DISPLAY1
            & `$multiTool /SetPrimary \\.\DISPLAY1
        }
    }
}
catch {
    Write-Log "ERROR: `$(`$_.Exception.Message)"
}
"@

Write-Config "$ToolsDir\teardown_sunvdm.ps1" $teardownScript

# ---------------------------------------------------------------------------
# 5. ADVANCEDRUN CONFIGS (NO BATCH WRAPPERS)
# ---------------------------------------------------------------------------
Write-Host 'Generating AdvancedRun configs...' -ForegroundColor Cyan

# Name      = ExePath | Args | StartDir | RunAs | WindowState | WaitProcess
$Apps = @{
    'setup'    = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$ToolsDir\setup_sunvdm.ps1`"|$ToolsDir|3|0|1"
    'teardown' = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$ToolsDir\teardown_sunvdm.ps1`"|$ToolsDir|3|0|1"
    'steam'    = "C:\Windows\explorer.exe|steam://open/bigpicture|C:\Windows|1|0|0"
    'xbox'     = "C:\Windows\explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\Windows|1|0|0"
    'playnite' = "$playniteExe||$(Split-Path -Path $playniteExe)|1|3|0"
    'esde'     = "$env:APPDATA\EmuDeck\Emulators\ES-DE\ES-DE.exe||$env:APPDATA\EmuDeck\Emulators\ES-DE|1|3|0"
    'sleep'    = "C:\Windows\System32\rundll32.exe|powrprof.dll,SetSuspendState 0,1,0|C:\Windows\System32|3|0|0"
    'restart'  = "C:\Windows\System32\shutdown.exe|/r /t 0|C:\Windows\System32|3|0|0"
    'taskmgr'  = "C:\Windows\System32\Taskmgr.exe||C:\Windows\System32|3|1|0"
    'browser'  = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe|--kiosk https://www.youtube.com/tv --edge-kiosk-type=fullscreen|C:\Program Files (x86)\Microsoft\Edge\Application|1|3|0"
}

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
                  "ParseVarInsideCmdLine=1"

    Write-Config $cfgPath $cfgContent
}

# ---------------------------------------------------------------------------
# 6. DOWNLOAD COVER ART
# ---------------------------------------------------------------------------
Write-Host 'Downloading App Cover Art...' -ForegroundColor Cyan

if (-not (Test-Path $SunshineCoversDir)) {
    New-Item -ItemType Directory -Force -Path $SunshineCoversDir | Out-Null
}

foreach ($img in $Covers.Keys) {
    $dest = "$SunshineCoversDir\$img"
    if (-not (Test-Path $dest)) {
        try {
            Invoke-WebRequest -Uri $Covers[$img] -OutFile $dest -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' -UseBasicParsing
            Write-Host " + Downloaded $img"
        } catch {
            Write-Warning "Failed to download $img"
        }
    }
}

# ---------------------------------------------------------------------------
# 7. DEPLOY SUNSHINE CONFIGS
# ---------------------------------------------------------------------------
Write-Host 'Updating Sunshine Configuration...' -ForegroundColor Cyan

if (Test-Path $SunshineConfigDir) {

    # Backup existing config files once
    foreach ($file in @('sunshine.conf','apps.json')) {
        $path = Join-Path $SunshineConfigDir $file
        if (Test-Path $path -and -not (Test-Path "$path.bak")) {
            Copy-Item $path "$path.bak" -Force
            Write-Host "Backed up $file to $file.bak" -ForegroundColor DarkGray
        }
    }

    # global_prep_cmd: call PowerShell scripts directly via cmd, elevated
    $confContent = 'global_prep_cmd = [{"do":"cmd /C powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\\\Sunshine-Tools\\\\setup_sunvdm.ps1\" > \"C:\\\\Sunshine-Tools\\\\sunvdm.log\" 2>&1","undo":"cmd /C powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\\\Sunshine-Tools\\\\teardown_sunvdm.ps1\" >> \"C:\\\\Sunshine-Tools\\\\sunvdm.log\" 2>&1","elevated":true}]'
    Write-Config "$SunshineConfigDir\sunshine.conf" $confContent

    # apps.json: call AdvancedRun configs directly (no batch files)
    $appsContent = @'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "covers\\desktop.png" },
    { "name": "Steam Big Picture", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_steam.cfg", "undo": "" } ], "image-path": "covers\\steam.png" },
    { "name": "Xbox (Game Pass)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_xbox.cfg", "undo": "" } ], "image-path": "covers\\xbox.png" },
    { "name": "Playnite", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_playnite.cfg", "undo": "" } ], "image-path": "covers\\playnite.png" },
    { "name": "EmulationStation", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_esde.cfg", "undo": "" } ], "image-path": "covers\\esde.png" },
    { "name": "YouTube TV", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_browser.cfg", "undo": "" } ], "image-path": "covers\\browser.png" },
    { "name": "Task Manager (Rescue)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_taskmgr.cfg", "undo": "" } ], "image-path": "covers\\taskmgr.png" },
    { "name": "Sleep PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_sleep.cfg", "undo": "" } ], "image-path": "covers\\sleep.png" },
    { "name": "Restart PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\AdvancedRun.exe /Run C:\\Sunshine-Tools\\cfg_restart.cfg", "undo": "" } ], "image-path": "covers\\restart.png" }
  ]
}
'@
    Write-Config "$SunshineConfigDir\apps.json" $appsContent
} else {
    Write-Warning "Sunshine config directory '$SunshineConfigDir' not found. Skipping Sunshine config update."
}

# ---------------------------------------------------------------------------
# 8. FINAL CLEANUP & RESTART
# ---------------------------------------------------------------------------
Write-Host 'Unblocking files...' -ForegroundColor Cyan
Get-ChildItem -Path $ToolsDir -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

Write-Host 'Restarting Sunshine...' -ForegroundColor Cyan
Stop-Service 'Sunshine Service' -ErrorAction SilentlyContinue
Get-Process 'sunshine' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service 'Sunshine Service' -ErrorAction SilentlyContinue

Write-Host '>>> COMPLETE! Your Custom Sunshine Host is Ready. <<<' -ForegroundColor Green
