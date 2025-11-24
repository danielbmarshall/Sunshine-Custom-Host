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
    'restart.png'  = 'https://icons.iconarchive.com/icons/oxygen-icons.org/oxygen/128/Actions-system-reboot-icon.png'
    'browser.png'  = 'https://upload.wikimedia.org/wikipedia/commons/8/87/Google_Chrome_icon_%282011%29.png'
    'desktop.png'  = 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Windows_11_logo.svg/512px-Windows_11_logo.svg.png'
}

# --- Admin Check --------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-Error 'Please run this script as Administrator!'
    exit 1
}

# --- Helper: Write UTF8 (no BOM) ---------------------------------------------
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
    $args = "install --id $Id -e --silent --accept-package-agreements --accept-source-agreements"
    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($proc.ExitCode -ne 0) {
        Write-Warning "winget install for $Id exited with code $($proc.ExitCode)."
    }
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
Set-Acl -Path $ToolsDir -AclObject $acl   # named parameters to avoid binding issues

# ---------------------------------------------------------------------------
# 2. INSTALL SOFTWARE (SUNSHINE, PLAYNITE, VDD)
# ---------------------------------------------------------------------------

# Sunshine (service name or display name)
Write-Host 'Checking for Sunshine...' -ForegroundColor Cyan
$sunshineService = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'SunshineService' -or $_.DisplayName -eq 'Sunshine Service' }

if (-not $sunshineService) {
    Install-WingetApp -Id 'LizardByte.Sunshine'
    Start-Sleep -Seconds 5
    $sunshineService = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'SunshineService' -or $_.DisplayName -eq 'Sunshine Service' }
    if (-not $sunshineService) {
        Write-Warning 'Sunshine service still not found after install. Please verify manually.'
    }
} else {
    Write-Host 'Sunshine already installed.' -ForegroundColor Green
}

# Playnite
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
$vddCheck = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match 'Idd' -or $_.FriendlyName -match 'MTT' }

if (-not $vddCheck) {
    Write-Host 'Installing VDD...' -ForegroundColor Yellow
    $vddUrl = 'https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/24.12.24/Signed-Driver-v24.12.24-x64.zip'
    $vddZip = "$env:TEMP\vdd.zip"
    $vddDir = 'C:\VirtualDisplayDriver'

    Invoke-WebRequest -Uri $vddUrl -OutFile $vddZip -UseBasicParsing

    if (Test-Path $vddDir) {
        Remove-Item $vddDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $vddDir | Out-Null

    Expand-Archive -Path $vddZip -DestinationPath "$env:TEMP\vdd_extract" -Force
    Get-ChildItem -Path "$env:TEMP\vdd_extract" -Recurse -File | Copy-Item -Destination $vddDir -Force

    pnputil /add-driver "$vddDir\MttVDD.inf" /install
} else {
    Write-Host 'VDD already installed.' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. DEPLOY HELPER TOOLS
# ---------------------------------------------------------------------------
Write-Host 'Deploying helper tools...' -ForegroundColor Cyan

$Downloads = @(
    @{ Name = 'MultiMonitorTool'; Url = 'https://www.nirsoft.net/utils/multimonitortool-x64.zip' },
    @{ Name = 'AdvancedRun';      Url = 'https://www.nirsoft.net/utils/advancedrun-x64.zip' },
    @{ Name = 'WinDisplayMgr';    Url = 'https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip' }
)

foreach ($tool in $Downloads) {
    $zipPath = "$ToolsDir\$($tool.Name).zip"

    if ($tool.Name -in @('MultiMonitorTool','AdvancedRun')) {
        if (-not (Test-Path "$ToolsDir\$($tool.Name).exe")) {
            Write-Host "Downloading $($tool.Name)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
            Remove-Item $zipPath -Force
        }
    } else {
        if (-not (Test-Path "$ToolsDir\WindowsDisplayManager")) {
            Write-Host 'Downloading WindowsDisplayManager...' -ForegroundColor Yellow
            Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
            Remove-Item $zipPath -Force
            if (Test-Path "$ToolsDir\WindowsDisplayManager-master") {
                Rename-Item -Path "$ToolsDir\WindowsDisplayManager-master" -NewName 'WindowsDisplayManager' -Force
            }
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
            `$virtual  = `$monitors | Where-Object { `$_.MonitorID -match 'MTT' -or `$_.MonitorName -match 'VDD' -or `$_.Name -match 'VDD' }
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
    Write-L
