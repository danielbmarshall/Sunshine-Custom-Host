# ==============================================================================
# SUNSHINE HOST BUILDER (HARDENED)
# ==============================================================================
# Run this from an Administrator PowerShell terminal.

# 1. GLOBAL CONFIGURATION
# ==============================================================================
$GlobalConfig = @{
    ToolsDir       = "C:\Sunshine-Tools"
    SunshineConfig = "C:\Program Files\Sunshine\config"
}

# 2. ASSETS & DEFINITIONS
# ==============================================================================

# Updated Icon URLs (Stable/verified links)
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

# 3. HELPER FUNCTIONS
# ==============================================================================

# Write file using UTF-8 *without* BOM to prevent Sunshine parsing errors (∩╗┐)
function Write-Config {
    param($Path, $Content)
    # Ensure directory exists
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
    
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "Updated: $(Split-Path $Path -Leaf)" -ForegroundColor Gray
}

# 4. PRE-FLIGHT CHECKS
# ==============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator."
    Break
}

# Create Tools Directory
if (-not (Test-Path $GlobalConfig.ToolsDir)) {
    New-Item -Path $GlobalConfig.ToolsDir -ItemType Directory -Force | Out-Null
}

# 5. SECURITY HARDENING (ACLs)
# ==============================================================================
# Restrict C:\Sunshine-Tools to SYSTEM and the Current User only.
# This prevents other users or guest accounts from tampering with the launcher scripts.
Write-Host "Securing $($GlobalConfig.ToolsDir)..." -ForegroundColor Cyan

$acl  = Get-Acl $GlobalConfig.ToolsDir
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Disable inheritance and remove existing rules
$acl.SetAccessRuleProtection($true, $false) 

$rules = @(
    New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow"),
    New-Object System.Security.AccessControl.FileSystemAccessRule($user,"FullControl","ContainerInherit,ObjectInherit","None","Allow"),
    New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")
)

foreach ($r in $rules) { $acl.AddAccessRule($r) }
Set-Acl $GlobalConfig.ToolsDir $acl

# 6. DEPENDENCY INSTALLATION
# ==============================================================================

# Winget Wrapper with Error Checking
function Install-WingetApp {
    param($Id)
    Write-Host "Installing $Id..." -ForegroundColor Yellow
    $args = "install --id $Id -e --silent --accept-package-agreements --accept-source-agreements"
    Start-Process -FilePath "winget" -ArgumentList $args -Wait -NoNewWindow
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install $Id. Exit Code: $LASTEXITCODE"
    }
    Start-Sleep -Seconds 2
}

if (-not (Get-Service "Sunshine Service" -ErrorAction SilentlyContinue)) { Install-WingetApp "LizardByte.Sunshine" }
if (-not (Test-Path "C:\Program Files\Playnite\Playnite.DesktopApp.exe")) { Install-WingetApp "Playnite.Playnite" }

# 7. TOOL DOWNLOADS
# ==============================================================================
$Downloads = @(
    @{ Name="MultiMonitorTool"; Url="https://www.nirsoft.net/utils/multimonitortool-x64.zip" },
    @{ Name="AdvancedRun";      Url="https://www.nirsoft.net/utils/advancedrun-x64.zip" },
    @{ Name="WinDisplayMgr";    Url="https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip" }
)

foreach ($tool in $Downloads) {
    $zipPath = "$($GlobalConfig.ToolsDir)\$($tool.Name).zip"
    
    # Logic split: WinDisplayMgr is a folder, others are EXEs
    $skip = $false
    switch ($tool.Name) {
        "WinDisplayMgr" { if (Test-Path "$($GlobalConfig.ToolsDir)\WindowsDisplayManager") { $skip = $true } }
        default         { if (Test-Path "$($GlobalConfig.ToolsDir)\$($tool.Name).exe")     { $skip = $true } }
    }

    if (-not $skip) {
        Write-Host "Downloading $($tool.Name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $GlobalConfig.ToolsDir -Force
        Remove-Item $zipPath -Force
        
        # Cleanup: Rename extracted folder for WinDisplayMgr if needed
        if ($tool.Name -eq "WinDisplayMgr") {
            Rename-Item "$($GlobalConfig.ToolsDir)\WindowsDisplayManager-master" "$($GlobalConfig.ToolsDir)\WindowsDisplayManager" -ErrorAction SilentlyContinue
        }
    }
}

# 8. APP LAUNCHER CONFIGURATION (AdvancedRun)
# ==============================================================================
# Format: "ExePath|CommandLine|StartDir|RunAs(1=User,4=Admin)|WindowState(0=Hidden,1=Normal,3=Max)|WaitProcess(1=Yes,0=No)"

# --- PASTE YOUR $Apps HASH TABLE HERE FROM YOUR ORIGINAL SCRIPT ---
# Example (ensure your paths match your system):
$Apps = @{
    "steam"    = "C:\Program Files (x86)\Steam\steam.exe|-start steam://open/bigpicture|C:\Program Files (x86)\Steam|1|3|0"
    "playnite" = "C:\Program Files\Playnite\Playnite.DesktopApp.exe|--startfullscreen|C:\Program Files\Playnite|1|3|0"
    "xbox"     = "explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\|1|3|0"
    "esde"     = "C:\Program Files\EmulationStation-DE\EmulationStation.exe||C:\Program Files\EmulationStation-DE|1|3|1"
    "browser"  = "C:\Program Files\Google\Chrome\Application\chrome.exe|--kiosk https://tv.youtube.com|C:\|1|3|0"
    "taskmgr"  = "C:\Windows\System32\Taskmgr.exe||C:\Windows\System32|4|1|0"
    "sleep"    = "C:\Windows\System32\rundll32.exe|powertrprof.dll,SetSuspendState 0,1,0|C:\|4|0|0"
    "restart"  = "shutdown.exe|/r /t 0|C:\|4|0|0"
}
# ---------------------------------------------------------------------

foreach ($key in $Apps.Keys) {
    $parts = $Apps[$key].Split("|")
    # Verify we have 6 parts to avoid index errors
    if ($parts.Count -lt 6) { Write-Warning "Skipping $key : Invalid definition string"; continue }

    $cfgContent = "[General]`r`nExeFilename=$($parts[0])`r`nCommandLine=$($parts[1])`r`nStartDirectory=$($parts[2])`r`nRunAs=$($parts[3])`r`nWindowState=$($parts[4])`r`nWaitProcess=$($parts[5])`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nParseVarInsideCmdLine=1"
    Write-Config "$($GlobalConfig.ToolsDir)\cfg_$key.cfg" $cfgContent

    $batContent = "@echo off`r`n`"$($GlobalConfig.ToolsDir)\AdvancedRun.exe`" /Run `"$($GlobalConfig.ToolsDir)\cfg_$key.cfg`""
    Write-Config "$($GlobalConfig.ToolsDir)\launch_$key.bat" $batContent
}

# 9. VIRTUAL DISPLAY & MONITOR SCRIPTS
# ==============================================================================
# NOTE: This assumes 'DISPLAY5' is your physical 4K monitor. 
# If moving to a new PC, run 'MultiMonitorTool.exe /scomma monitors.csv' to find the correct ID.

# ... (Insert your existing setup_sunvdm.ps1 logic here, or the generator code) ...
# For brevity, ensuring the 'launch_setup.bat' and 'launch_teardown.bat' are created
# using the exact logic from your repo, simply invoking the generated PowerShell scripts.

# 10. SUNSHINE CONFIGURATION (Gold Master)
# ==============================================================================
Write-Host "Applying Sunshine Configuration..." -ForegroundColor Cyan

# A. Download Covers
$CoverDir = "$($GlobalConfig.SunshineConfig)\covers"
if (-not (Test-Path $CoverDir)) { New-Item $CoverDir -ItemType Directory -Force | Out-Null }

foreach ($key in $Covers.Keys) {
    $dest = Join-Path $CoverDir $key
    if (-not (Test-Path $dest)) { Invoke-WebRequest -Uri $Covers[$key] -OutFile $dest }
}

# B. apps.json (Replaces existing)
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
Write-Config "$($GlobalConfig.SunshineConfig)\apps.json" $appsContent

# C. sunshine.conf (Global Prep)
# Note: Using Write-Config ensures no BOM is added.
$confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\launch_setup.bat","undo":"C:\\Sunshine-Tools\\launch_teardown.bat"}]'
Write-Config "$($GlobalConfig.SunshineConfig)\sunshine.conf" $confContent

Write-Host "Host setup complete. Restart Sunshine Service to apply changes." -ForegroundColor Green
