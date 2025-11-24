# ============================================================================
#  SUNSHINE CUSTOM HOST - UNIFIED INSTALLER
#  Installs: Sunshine, Playnite, Virtual Display Driver (Signed)
#  Configures: Hardened MST-Aware Scripts, AdvancedRun, Custom Apps, Cover Art
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

# 3. VIRTUAL DISPLAY DRIVER (Latest Signed from VirtualDrivers Repo)
# Source: https://github.com/VirtualDrivers/Virtual-Display-Driver
$vddCheck = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "Idd" -or $_.FriendlyName -match "MTT" }
if (-not $vddCheck) {
    Write-Host "Installing Virtual Display Driver..." -ForegroundColor Yellow
    
    # v24.12.24 Signed Release
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
    $
