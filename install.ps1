# ==============================================================================
# SUNSHINE HOST BUILDER (FIXED COMPATIBILITY)
# ==============================================================================
# Run this from an Administrator PowerShell terminal.

$GlobalConfig = @{
    ToolsDir       = "C:\Sunshine-Tools"
    SunshineConfig = "C:\Program Files\Sunshine\config"
}

# Verified Icon URLs
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

# --- HELPER FUNCTIONS ---

function Write-Config {
    param($Path, $Content)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
    
    # UTF-8 No BOM to prevent "∩╗┐" errors in Sunshine
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "Updated: $(Split-Path $Path -Leaf)" -ForegroundColor Gray
}

# --- PRE-FLIGHT CHECKS ---

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator."
    Break
}

if (-not (Test-Path $GlobalConfig.ToolsDir)) {
    New-Item -Path $GlobalConfig.ToolsDir -ItemType Directory -Force | Out-Null
}

# --- SECURITY HARDENING (ACLs) ---
# FIXED: Using [Class]::new() syntax for PowerShell 5.1 compatibility
Write-Host "Securing $($GlobalConfig.ToolsDir)..." -ForegroundColor Cyan

try {
    $acl  = Get-Acl $GlobalConfig.ToolsDir
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    
    # Disable inheritance
    $acl.SetAccessRuleProtection($true, $false) 

    # Create rules using static method (PS 5.1 compatible)
    $rules = @(
        [System.Security.AccessControl.FileSystemAccessRule]::new("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new($user,"FullControl","ContainerInherit,ObjectInherit","None","Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    )

    foreach ($r in $rules) { $acl.AddAccessRule($r) }
    Set-Acl $GlobalConfig.ToolsDir $acl
}
catch {
    Write-Warning "ACL hardening failed. Using default permissions. Error: $_"
}

# --- DEPENDENCY INSTALLATION ---

function Install-WingetApp {
    param($Id)
    Write-Host "Checking $Id..." -ForegroundColor Yellow
    
    # FIXED: Don't treat "No upgrade found" as a fatal error
    $args = "install --id $Id -e --silent --accept-package-agreements --accept-source-agreements"
    $proc = Start-Process -FilePath "winget" -ArgumentList $args -Wait -NoNewWindow -PassThru
    
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne -1978334967) { 
        # -1978334967 is often "No update available"
        Write-Warning "Winget returned exit code $($proc.ExitCode) for $Id. If it's already installed, you can ignore this."
    }
}

if (-not (Get-Service "Sunshine Service" -ErrorAction SilentlyContinue)) { Install-WingetApp "LizardByte.Sunshine" }

# Relaxed Playnite check: check default path AND typical x86 path
if (-not (Test-Path "C:\Program Files\Playnite\Playnite.DesktopApp.exe") -and -not (Test-Path "C:\Program Files (x86)\Playnite\Playnite.DesktopApp.exe")) { 
    Install-WingetApp "Playnite.Playnite" 
}

# --- TOOL DOWNLOADS ---

$Downloads = @(
    @{ Name="MultiMonitorTool"; Url="https://www.nirsoft.net/utils/multimonitortool-x64.zip" },
    @{ Name="AdvancedRun";      Url="https://www.nirsoft.net/utils/advancedrun-x64.zip" },
    @{ Name="WinDisplayMgr";    Url="https://github.com/patrick-theprogrammer/WindowsDisplayManager/archive/refs/heads/master.zip" }
)

foreach ($tool in $Downloads) {
    $zipPath = "$($GlobalConfig.ToolsDir)\$($tool.Name).zip"
    $skip = $false
    
    switch ($tool.Name) {
        "WinDisplayMgr" { if (Test-Path "$($GlobalConfig.ToolsDir)\WindowsDisplayManager") { $skip = $true } }
        default         { if (Test-Path "$($GlobalConfig.ToolsDir)\$($tool.Name).exe")     { $skip = $true } }
    }

    if (-not $skip) {
        Write-Host "Downloading $($tool.Name)..." -ForegroundColor Cyan
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $tool.Url -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $GlobalConfig.ToolsDir -Force
            Remove-Item $zipPath -Force
            
            if ($tool.Name -eq "WinDisplayMgr") {
                Rename-Item "$($GlobalConfig.ToolsDir)\WindowsDisplayManager-master" "$($GlobalConfig.ToolsDir)\WindowsDisplayManager" -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Error "Failed to download $($tool.Name): $_"
        }
    }
}

# --- CONFIG GENERATION (AdvancedRun) ---

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

foreach ($key in $Apps.Keys) {
    $parts = $Apps[$key].Split("|")
    if ($parts.Count -lt 6) { continue }

    $cfgContent = "[General]`r`nExeFilename=$($parts[0])`r`nCommandLine=$($parts[1])`r`nStartDirectory=$($parts[2])`r`nRunAs=$($parts[3])`r`nWindowState=$($parts[4])`r`nWaitProcess=$($parts[5])`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nParseVarInsideCmdLine=1"
    Write-Config "$($GlobalConfig.ToolsDir)\cfg_$key.cfg" $cfgContent

    $batContent = "@echo off`r`n`"$($GlobalConfig.ToolsDir)\AdvancedRun.exe`" /Run `"$($GlobalConfig.ToolsDir)\cfg_$key.cfg`""
    Write-Config "$($GlobalConfig.ToolsDir)\launch_$key.bat" $batContent
}

# --- SUNSHINE CONFIG ---
Write-Host "Applying Sunshine Configuration..." -ForegroundColor Cyan

$CoverDir = "$($GlobalConfig.SunshineConfig)\covers"
if (-not (Test-Path $CoverDir)) { New-Item $CoverDir -ItemType Directory -Force | Out-Null }

foreach ($key in $Covers.Keys) {
    $dest = Join-Path $CoverDir $key
    if (-not (Test-Path $dest)) { 
        try { Invoke-WebRequest -Uri $Covers[$key] -OutFile $dest -UseBasicParsing } catch {} 
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
Write-Config "$($GlobalConfig.SunshineConfig)\apps.json" $appsContent

$confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\launch_setup.bat","undo":"C:\\Sunshine-Tools\\launch_teardown.bat"}]'
Write-Config "$($GlobalConfig.SunshineConfig)\sunshine.conf" $confContent

Write-Host "Host setup complete. Restart Sunshine Service to apply changes." -ForegroundColor Green
