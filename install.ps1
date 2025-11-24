# ==============================================================================
# SUNSHINE HOST BUILDER (FINAL REFINED)
# ==============================================================================
# Run this from an Administrator PowerShell terminal.
# This script:
#   - Installs Sunshine + Playnite (via winget, if available)
#   - Installs helper tools (MultiMonitorTool, AdvancedRun, WindowsDisplayManager)
#   - Sets up a virtual display (VDD) workflow for Sunshine streaming
#   - Configures Sunshine apps.json and sunshine.conf
#   - Downloads cover art icons for the Sunshine UI
# ==============================================================================

$ErrorActionPreference = 'Stop'

# 1. GLOBAL CONFIGURATION
# ==============================================================================
$GlobalConfig = @{
    ToolsDir       = 'C:\Sunshine-Tools'
    SunshineConfig = 'C:\Program Files\Sunshine\config'
}

# Resolution settings for your virtual display (VDD)
$MonitorConfig = @{
    Width   = 3840
    Height  = 2160
    Refresh = 60
}

# Verified icon URLs
$Covers = @{
    'steam.png'    = 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Steam_icon_logo.svg/512px-Steam_icon_logo.svg.png'
    'playnite.png' = 'https://playnite.link/applogo.png'
    'xbox.png'     = 'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/Xbox_one_logo.svg/512px-Xbox_one_logo.svg.png'
    'esde.png'     = 'https://gitlab.com/uploads/-/system/project/avatar/18817634/emulationstation_1024x1024.png'
    'taskmgr.png'  = 'https://upload.wikimedia.org/wikipedia/commons/a/ac/Windows_11_TASKMGR.png'
    'sleep.png'    = 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Oxygen480-actions-system-suspend.svg/480px-Oxygen480-actions-system-suspend.svg.png'
    'restart.png'  = 'https://icons.iconarchive.com/icons/oxygen-icons.org/oxygen/128/Actions-system-reboot-icon.png'
    'browser.png'  = 'https://upload.wikimedia.org/wikipedia/commons/8/87/Google_Chrome_icon_%282011%29.png'
    'desktop.png'  = 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Windows_11_logo.svg/512px-Windows_11_logo.svg.png'
}

# 2. BASIC GUARDS & HELPERS
# ==============================================================================

# Require Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-Warning 'Please run this script as Administrator.'
    exit 1
}

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
        Write-Warning "winget.exe not found. Please install $Id manually."
        return
    }

    Write-Host "Installing $Id via winget..." -ForegroundColor Yellow
    $args = "install --id $Id -e --silent --accept-package-agreements --accept-source-agreements"
    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($proc.ExitCode -ne 0) {
        Write-Warning "winget install for $Id exited with code $($proc.ExitCode)."
    }
}

Write-Host '>>> Sunshine Host Builder starting...' -ForegroundColor Cyan

# 3. PREPARE TOOLS DIRECTORY & ACL
# ==============================================================================
$ToolsDir = $GlobalConfig.ToolsDir
if (-not (Test-Path $ToolsDir)) {
    New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
}

# Grant SYSTEM and current user full control (avoid Everyone:FullControl)
$acl  = Get-Acl $ToolsDir
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$rules = @(
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        'SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow'
    ),
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        $user,'FullControl','ContainerInherit,ObjectInherit','None','Allow'
    )
)

foreach ($rule in $rules) {
    $acl.SetAccessRule($rule)
}

Set-Acl -Path $ToolsDir -AclObject $acl

# 4. INSTALL SUNSHINE & PLAYNITE
# ==============================================================================
Write-Host 'Checking for Sunshine installation...' -ForegroundColor Cyan
$sunshineService = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'SunshineService' -or $_.DisplayName -eq 'Sunshine Service' }

if (-not $sunshineService) {
    Install-WingetApp -Id 'LizardByte.Sunshine'
    $sunshineService = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'SunshineService' -or $_.DisplayName -eq 'Sunshine Service' }
    if (-not $sunshineService) {
        Write-Warning 'Sunshine service still not found after install. Please verify manually.'
    }
} else {
    Write-Host 'Sunshine already installed.' -ForegroundColor Green
}

Write-Host 'Checking for Playnite installation...' -ForegroundColor Cyan
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

# 5. INSTALL/VERIFY TOOLS (MultiMonitorTool, AdvancedRun, WindowsDisplayManager)
# ==============================================================================
Write-Host 'Checking helper tools...' -ForegroundColor Cyan

$downloads = @(
    @{ Name = 'MultiMonitorTool'; Url = 'https://www.nirsoft.net/utils/multimonitortool-x64.zip'; Exe = 'MultiMonitorTool.exe' },
    @{ Name = 'AdvancedRun';      Url = 'https://www.nirsoft.net/utils/advancedrun-x64.zip';     Exe = 'AdvancedRun.exe' },
    @{ Name = 'WindowsDisplayManager'; Url = 'https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip'; Folder = 'WindowsDisplayManager' }
)

foreach ($tool in $downloads) {
    $zipPath = Join-Path $ToolsDir ("{0}.zip" -f $tool.Name)

    if ($tool.ContainsKey('Exe')) {
        $exePath = Join-Path $ToolsDir $tool.Exe
        if (-not (Test-Path $exePath)) {
            Write-Host "Downloading $($tool.Name)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
            Remove-Item $zipPath -Force
        }
    } elseif ($tool.ContainsKey('Folder')) {
        $folderPath = Join-Path $ToolsDir $tool.Folder
        if (-not (Test-Path $folderPath)) {
            Write-Host "Downloading $($tool.Name)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
            Remove-Item $zipPath -Force

            # GitHub archive extracts as WindowsDisplayManager-master; rename
            $extracted = Join-Path $ToolsDir 'WindowsDisplayManager-master'
            if (Test-Path $extracted) {
                Rename-Item -Path $extracted -NewName $tool.Folder -Force
            }
        }
    }
}

# 6. GENERATE VIRTUAL DISPLAY (VDD) SETUP/TEARDOWN SCRIPTS
# ==============================================================================
Write-Host 'Generating VDD setup/teardown scripts...' -ForegroundColor Cyan

$setupScript = @"
`$ErrorActionPreference = 'Stop'

`$LogPath    = Join-Path '$($GlobalConfig.ToolsDir)' 'sunvdm_log.txt'
`$ScriptPath = '$($GlobalConfig.ToolsDir)'
`$Width      = $($MonitorConfig.Width)
`$Height     = $($MonitorConfig.Height)
`$Refresh    = $($MonitorConfig.Refresh)

function Write-Log {
    param([string]`$Message)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path `$LogPath -Value "`$timestamp [SETUP] `$Message"
}

try {
    Write-Log 'Starting VDD setup.'

    `$multiTool    = Join-Path `$ScriptPath 'MultiMonitorTool.exe'
    `$configBackup = Join-Path `$ScriptPath 'monitor_config.cfg'
    `$csvPath      = Join-Path `$ScriptPath 'current_monitors.csv'

    if (-not (Test-Path `$multiTool)) {
        Write-Log 'MultiMonitorTool.exe not found. Aborting setup.'
        return
    }

    Write-Log 'Saving current monitor configuration.'
    & `$multiTool /SaveConfig "`$configBackup"

    # Enable any virtual display devices that are present but disabled
    `$vddDevices = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                   Where-Object { `$_.FriendlyName -match 'MTT' -or `$_.FriendlyName -match 'IddSample' -or `$_.FriendlyName -match 'VDD' }

    if (-not `$vddDevices) {
        Write-Log 'No virtual display devices found. Aborting setup.'
        return
    }

    foreach (`$dev in `$vddDevices) {
        if (`$dev.Status -ne 'OK') {
            Write-Log "Enabling virtual display device: `$(`$dev.FriendlyName)"
            Enable-PnpDevice -InstanceId `$dev.InstanceId -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Write-Log 'Waiting for virtual display to appear in MultiMonitorTool output...'
    `$maxTries = 40
    `$virtual  = $null

    for (`$i = 0; `$i -lt `$maxTries -and -not `$virtual; `$i++) {
        & `$multiTool /scomma "`$csvPath"
        if (Test-Path `$csvPath) {
            `$monitors = Import-Csv `$csvPath
            `$virtual  = `$monitors | Where-Object { `$_.MonitorID -match 'MTT' -or `$_.MonitorName -match 'VDD' }
        }
        if (-not `$virtual) {
            Start-Sleep -Milliseconds 250
        }
    }

    if (-not `$virtual) {
        Write-Log 'Virtual display not found after timeout. Restoring original configuration.'
        & `$multiTool /LoadConfig "`$configBackup"
        return
    }

    `$targetName = `$virtual[0].Name
    Write-Log "Using virtual display as primary: `$targetName"

    & `$multiTool /SetPrimary "`$targetName"
    & `$multiTool /Enable "`$targetName"

    Write-Log 'Disabling other active displays.'
    & `$multiTool /scomma "`$csvPath"
    `$monitors = Import-Csv `$csvPath

    foreach (`$m in `$monitors) {
        if (`$m.Active -eq 'Yes' -and `$m.Name -ne `$targetName) {
            Write-Log "Disabling display: `$(`$m.Name)"
            & `$multiTool /Disable "`$(`$m.Name)"
        }
    }

    # Set resolution using WindowsDisplayManager
    `$wdmFolder = Join-Path `$ScriptPath 'WindowsDisplayManager'
    `$wdmExe    = Join-Path `$wdmFolder 'WindowsDisplayManager.exe'

    if (Test-Path `$wdmExe) {
        Write-Log "Setting VDD resolution to `$Width x `$Height @ `$Refresh Hz"
        & `$wdmExe set-mode -w `$Width -h `$Height -r `$Refresh -d 0
    } else {
        Write-Log 'WindowsDisplayManager.exe not found. Skipping resolution step.'
    }

    Write-Log 'VDD setup completed successfully.'
}
catch {
    Write-Log "ERROR: `$($_.Exception.Message)"
}
"@

Write-Config (Join-Path $ToolsDir 'setup_sunvdm.ps1') $setupScript

$teardownScript = @"
`$ErrorActionPreference = 'Stop'

`$LogPath    = Join-Path '$($GlobalConfig.ToolsDir)' 'sunvdm_log.txt'
`$ScriptPath = '$($GlobalConfig.ToolsDir)'

function Write-Log {
    param([string]`$Message)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path `$LogPath -Value "`$timestamp [TEARDOWN] `$Message"
}

try {
    Write-Log 'Starting VDD teardown.'

    `$multiTool    = Join-Path `$ScriptPath 'MultiMonitorTool.exe'
    `$configBackup = Join-Path `$ScriptPath 'monitor_config.cfg'

    # Disable any virtual display devices that are enabled
    `$vddDevices = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                   Where-Object { `$_.FriendlyName -match 'MTT' -or `$_.FriendlyName -match 'IddSample' -or `$_.FriendlyName -match 'VDD' }

    foreach (`$dev in `$vddDevices) {
        if (`$dev.Status -eq 'OK') {
            Write-Log "Disabling virtual display device: `$(`$dev.FriendlyName)"
            Disable-PnpDevice -InstanceId `$dev.InstanceId -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
        }
    }

    if (Test-Path `$multiTool -and Test-Path `$configBackup) {
        Write-Log 'Restoring original monitor configuration.'
        & `$multiTool /LoadConfig "`$configBackup"
    } else {
        Write-Log 'MultiMonitorTool or backup config not found. Skipping restore.'
    }

    Write-Log 'VDD teardown completed.'
}
catch {
    Write-Log "ERROR: `$($_.Exception.Message)"
}
"@

Write-Config (Join-Path $ToolsDir 'teardown_sunvdm.ps1') $teardownScript

# 7. ADVANCEDRUN CONFIGS + BATCH WRAPPERS
# ==============================================================================
Write-Host 'Generating AdvancedRun configs and launchers...' -ForegroundColor Cyan

$Apps = @{
    # Name      = ExePath | Args | StartDir | RunAs | WindowState | WaitProcess
    'setup'    = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$ToolsDir\setup_sunvdm.ps1`"|$ToolsDir|3|0|1"
    'teardown' = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$ToolsDir\teardown_sunvdm.ps1`"|$ToolsDir|3|0|1"
    'steam'    = "C:\Windows\explorer.exe|steam://open/bigpicture|C:\Windows|1|0|0"
    'xbox'     = "C:\Windows\explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\Windows|1|0|0"
    'playnite' = "$env:LOCALAPPDATA\Playnite\Playnite.FullscreenApp.exe||$env:LOCALAPPDATA\Playnite|1|3|0"
    'esde'     = "$env:APPDATA\EmuDeck\Emulators\ES-DE\ES-DE.exe||$env:APPDATA\EmuDeck\Emulators\ES-DE|1|3|0"
    'sleep'    = "C:\Windows\System32\rundll32.exe|powrprof.dll,SetSuspendState 0,1,0|C:\|4|0|0"
    'restart'  = "C:\Windows\System32\shutdown.exe|/r /t 0|C:\Windows\System32|4|0|0"
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

    $batPath = Join-Path $ToolsDir ("launch_{0}.bat" -f $key)
    $batContent = "@echo off`r`n" +
                  "`"$ToolsDir\AdvancedRun.exe`" /Run `"$cfgPath`""
    Write-Config $batPath $batContent
}

# 8. CONFIGURE SUNSHINE (apps.json & sunshine.conf)
# ==============================================================================
Write-Host 'Configuring Sunshine (apps.json, sunshine.conf)...' -ForegroundColor Cyan

$SunshineConfigPath = $GlobalConfig.SunshineConfig
if (-not (Test-Path $SunshineConfigPath)) {
    Write-Warning "Sunshine config directory not found at '$SunshineConfigPath'. Skipping Sunshine config update."
} else {
    # Backup existing config files if present
    foreach ($file in @('apps.json','sunshine.conf')) {
        $path = Join-Path $SunshineConfigPath $file
        if (Test-Path $path) {
            Copy-Item $path "$path.bak" -Force
            Write-Host "Backed up $file to $file.bak" -ForegroundColor DarkGray
        }
    }

    $appsContent = @'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "covers\\desktop.png" },
    { "name": "Steam Big Picture", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_steam.bat", "undo": "" } ], "image-path": "covers\\steam.png" },
    { "name": "Xbox (Game Pass)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_xbox.bat", "undo": "" } ], "image-path": "covers\\xbox.png" },
    { "name": "Playnite", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_playnite.bat", "undo": "" } ], "image-path": "covers\\playnite.png" },
    { "name": "EmulationStation", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_esde.bat", "undo": "" } ], "image-path": "covers\\esde.png" },
    { "name": "YouTube TV", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_browser.bat", "undo": "" } ], "image-path": "covers\\browser.png" },
    { "name": "Task Manager (Rescue)", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_taskmgr.bat", "undo": "" } ], "image-path": "covers\\taskmgr.png" },
    { "name": "Sleep PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_sleep.bat", "undo": "" } ], "image-path": "covers\\sleep.png" },
    { "name": "Restart PC", "prep-cmd": [ { "do": "C:\\Sunshine-Tools\\launch_restart.bat", "undo": "" } ], "image-path": "covers\\restart.png" }
  ]
}
'@

    Write-Config (Join-Path $SunshineConfigPath 'apps.json') $appsContent

    $confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\launch_setup.bat","undo":"C:\\Sunshine-Tools\\launch_teardown.bat"}]'
    Write-Config (Join-Path $SunshineConfigPath 'sunshine.conf') $confContent
}

# 9. DOWNLOAD COVER ART
# ==============================================================================
Write-Host 'Downloading cover artwork...' -ForegroundColor Cyan

$CoverDir = Join-Path $SunshineConfigPath 'covers'
if (-not (Test-Path $CoverDir)) {
    New-Item -ItemType Directory -Path $CoverDir -Force | Out-Null
}

foreach ($key in $Covers.Keys) {
    $dest = Join-Path $CoverDir $key
    if (-not (Test-Path $dest)) {
        try {
            Invoke-WebRequest -Uri $Covers[$key] -OutFile $dest -UseBasicParsing -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
            Write-Host "Downloaded $key" -ForegroundColor DarkGreen
        } catch {
            Write-Warning "Failed to download $key from $($Covers[$key])"
        }
    }
}

# 10. FINAL CLEANUP & SUNSHINE RESTART
# ==============================================================================
Write-Host 'Unblocking downloaded tools...' -ForegroundColor Cyan
Get-ChildItem -Path $ToolsDir -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

if ($sunshineService) {
    Write-Host 'Restarting Sunshine service...' -ForegroundColor Cyan
    try {
        Stop-Service $sunshineService.Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Service $sunshineService.Name -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Could not restart Sunshine service: $($_.Exception.Message)"
    }
}

Write-Host '>>> Host setup complete. Sunshine should now show your custom apps and artwork.' -ForegroundColor Green
