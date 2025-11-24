This is valid, actionable feedback. The `Break` command in a raw script was indeed a mistake (it only works inside loops), and `powertrprof.dll` was a genuine typo that would have silently failed.

Here is the **Final Refined** version of the script.

### **Changes Applied**

1.  **Fixed Admin Check:** Replaced `Break` with `exit 1` to correctly halt execution if not Admin.
2.  **Fixed Sleep Command:** Corrected `powertrprof.dll` to `powrprof.dll`.
3.  **Added Safety Backups:** The script now creates `.bak` copies of `apps.json` and `sunshine.conf` before overwriting them.
4.  **Winget Guard:** Wrapped the installation logic to check if `winget` exists first.
5.  **Parameterized Resolution:** Added a `$MonitorConfig` block at the top so you can change the target resolution (4K/60Hz) without hunting through the here-strings.

### **Final `install.ps1`**

```powershell
# ==============================================================================
# SUNSHINE HOST BUILDER (FINAL REFINED)
# ==============================================================================
# Run this from an Administrator PowerShell terminal.

# 1. GLOBAL CONFIGURATION
# ==============================================================================
$GlobalConfig = @{
    ToolsDir       = "C:\Sunshine-Tools"
    SunshineConfig = "C:\Program Files\Sunshine\config"
}

# Resolution settings for your Virtual Display (VDD)
$MonitorConfig = @{
    Width   = 3840
    Height  = 2160
    Refresh = 60
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

# 2. HELPER FUNCTIONS
# ==============================================================================

function Write-Config {
    param($Path, $Content)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
    
    # Backup existing config if present
    if (Test-Path $Path) {
        Copy-Item $Path "$Path.bak" -Force
        Write-Host "Backed up: $(Split-Path $Path -Leaf).bak" -ForegroundColor DarkGray
    }

    # UTF-8 No BOM to prevent "∩╗┐" errors in Sunshine
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "Updated: $(Split-Path $Path -Leaf)" -ForegroundColor Gray
}

# 3. PRE-FLIGHT CHECKS
# ==============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator."
    exit 1
}

if (-not (Test-Path $GlobalConfig.ToolsDir)) {
    New-Item -Path $GlobalConfig.ToolsDir -ItemType Directory -Force | Out-Null
}

# 4. SECURITY HARDENING (ACLs)
# ==============================================================================
Write-Host "Securing $($GlobalConfig.ToolsDir)..." -ForegroundColor Cyan
try {
    $acl  = Get-Acl $GlobalConfig.ToolsDir
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl.SetAccessRuleProtection($true, $false) # Disable inheritance

    # Allow SYSTEM, Current User, and Administrators only
    $rules = @(
        [System.Security.AccessControl.FileSystemAccessRule]::new("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new($user,"FullControl","ContainerInherit,ObjectInherit","None","Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    )
    foreach ($r in $rules) { $acl.AddAccessRule($r) }
    Set-Acl $GlobalConfig.ToolsDir $acl
}
catch { Write-Warning "ACL hardening failed. Using default permissions." }

# 5. DEPENDENCY INSTALLATION
# ==============================================================================

# Check for Winget availability
if (Get-Command "winget" -ErrorAction SilentlyContinue) {
    
    function Install-WingetApp {
        param($Id)
        Write-Host "Checking $Id..." -ForegroundColor Yellow
        $args = "install --id $Id -e --silent --accept-package-agreements --accept-source-agreements"
        $proc = Start-Process -FilePath "winget" -ArgumentList $args -Wait -NoNewWindow -PassThru
        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne -1978334967) { 
            Write-Warning "Winget code $($proc.ExitCode) for $Id (Ignore if already installed)."
        }
    }

    # Check for Service Name OR Display Name to be robust
    $sunshineSvc = Get-Service | Where-Object { $_.Name -eq 'SunshineService' -or $_.DisplayName -eq 'Sunshine Service' }
    if (-not $sunshineSvc) { Install-WingetApp "LizardByte.Sunshine" }

    if (-not (Test-Path "C:\Program Files\Playnite\Playnite.DesktopApp.exe") -and -not (Test-Path "C:\Program Files (x86)\Playnite\Playnite.DesktopApp.exe")) { 
        Install-WingetApp "Playnite.Playnite" 
    }

} else {
    Write-Warning "Winget not found. Skipping automatic application installation."
}

# 6. TOOL DOWNLOADS
# ==============================================================================
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
        } catch { Write-Error "Failed to download $($tool.Name): $_" }
    }
}

# 7. VIRTUAL MONITOR SCRIPTS (Dynamic Generation)
# ==============================================================================
# NOTE: The logic below defaults to "\\.\DISPLAY5" as the physical monitor.
# If you change ports or GPUs, you must update the "SetPrimary" line below.

$SetupScript = @"
`$LogPath = "$($GlobalConfig.ToolsDir)\sunvdm_log.txt"
Start-Transcript -Path `$LogPath -Append
`$ScriptPath = "$($GlobalConfig.ToolsDir)"

# 1. Save Config
& "`$ScriptPath\MultiMonitorTool.exe" /SaveConfig "`$ScriptPath\monitor_config.cfg"

# 2. Enable VDD (Idd or MTT)
Write-Host "Enabling VDD..."
Get-PnpDevice | Where-Object { (`$_.FriendlyName -like "*IddSampleDriver*" -or `$_.FriendlyName -like "*IddMonitor*") -and `$_.Status -eq "Error" } | Enable-PnpDevice -Confirm:`$false

# 3. Wait for VDD
Write-Host "Waiting for VDD..."
for (`$i=0; `$i -lt 10; `$i++) {
    & "`$ScriptPath\MultiMonitorTool.exe" /scomma "`$ScriptPath\monitors.csv"
    `$monitors = Import-Csv "`$ScriptPath\monitors.csv"
    `$virtual_mon = `$monitors | Where-Object { `$_.Name -match "VDD" -or `$_.MonitorID -match "MTT" }
    if (`$virtual_mon) { break }
    Start-Sleep -Milliseconds 500
}

if (`$virtual_mon) {
    # 4. Set VDD Primary
    Write-Host "Activating VDD (`$(`$virtual_mon.Name))..."
    & "`$ScriptPath\MultiMonitorTool.exe" /SetPrimary `$(`$virtual_mon.Name) 
    
    # 5. Disable others
    foreach (`$m in `$monitors) {
        if (`$m.Name -ne `$virtual_mon.Name) {
            & "`$ScriptPath\MultiMonitorTool.exe" /Disable `$(`$m.Name)
        }
    }

    # 6. Set Resolution ($($MonitorConfig.Width)x$($MonitorConfig.Height) @ $($MonitorConfig.Refresh)Hz)
    Start-Sleep -Milliseconds 500
    & "`$ScriptPath\WindowsDisplayManager\WindowsDisplayManager.exe" set-mode -d 0 -w $($MonitorConfig.Width) -h $($MonitorConfig.Height) -r $($MonitorConfig.Refresh)
}
Stop-Transcript
"@
Write-Config "$($GlobalConfig.ToolsDir)\setup_sunvdm.ps1" $SetupScript

$TeardownScript = @"
`$LogPath = "$($GlobalConfig.ToolsDir)\sunvdm_log.txt"
Start-Transcript -Path `$LogPath -Append
`$ScriptPath = "$($GlobalConfig.ToolsDir)"

# Restore Primary (Targeting DISPLAY5 - Your 4K Monitor)
Write-Host "Restoring Physical Monitor..."
& "`$ScriptPath\MultiMonitorTool.exe" /SetPrimary \\.\DISPLAY5
& "`$ScriptPath\MultiMonitorTool.exe" /LoadConfig "`$ScriptPath\monitor_config.cfg"

# Disable VDD
Get-PnpDevice | Where-Object { (`$_.FriendlyName -like "*IddSampleDriver*" -or `$_.FriendlyName -like "*IddMonitor*") -and `$_.Status -eq "OK" } | Disable-PnpDevice -Confirm:`$false

Stop-Transcript
"@
Write-Config "$($GlobalConfig.ToolsDir)\teardown_sunvdm.ps1" $TeardownScript


# 8. APP LAUNCHER CONFIGURATION
# ==============================================================================
# Includes Setup/Teardown to ensure launch_setup.bat and launch_teardown.bat are generated

$Apps = @{
    "setup"    = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$($GlobalConfig.ToolsDir)\setup_sunvdm.ps1`"|$($GlobalConfig.ToolsDir)|3|0|1"
    "teardown" = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe|-ExecutionPolicy Bypass -File `"$($GlobalConfig.ToolsDir)\teardown_sunvdm.ps1`"|$($GlobalConfig.ToolsDir)|3|0|1"
    "steam"    = "C:\Program Files (x86)\Steam\steam.exe|-start steam://open/bigpicture|C:\Program Files (x86)\Steam|1|3|0"
    "playnite" = "C:\Program Files\Playnite\Playnite.DesktopApp.exe|--startfullscreen|C:\Program Files\Playnite|1|3|0"
    "xbox"     = "explorer.exe|shell:AppsFolder\Microsoft.GamingApp_8wekyb3d8bbwe!Microsoft.Xbox.App|C:\|1|3|0"
    "esde"     = "C:\Program Files\EmulationStation-DE\EmulationStation.exe||C:\Program Files\EmulationStation-DE|1|3|1"
    "browser"  = "C:\Program Files\Google\Chrome\Application\chrome.exe|--kiosk https://tv.youtube.com|C:\|1|3|0"
    "taskmgr"  = "C:\Windows\System32\Taskmgr.exe||C:\Windows\System32|4|1|0"
    "sleep"    = "C:\Windows\System32\rundll32.exe|powrprof.dll,SetSuspendState 0,1,0|C:\|4|0|0"
    "restart"  = "shutdown.exe|/r /t 0|C:\|4|0|0"
}

foreach ($key in $Apps.Keys) {
    $parts = $Apps[$key].Split("|")
    if ($parts.Count -lt 6) { continue }
    
    $cfgName = "cfg_$key.cfg"
    $cfgContent = "[General]`r`nExeFilename=$($parts[0])`r`nCommandLine=$($parts[1])`r`nStartDirectory=$($parts[2])`r`nRunAs=$($parts[3])`r`nWindowState=$($parts[4])`r`nWaitProcess=$($parts[5])`r`nRunAsProcessMode=1`r`nPriorityClass=3`r`nParseVarInsideCmdLine=1"
    Write-Config "$($GlobalConfig.ToolsDir)\$cfgName" $cfgContent

    # Generate: launch_steam.bat, launch_setup.bat, etc.
    $batContent = "@echo off`r`n`"$($GlobalConfig.ToolsDir)\AdvancedRun.exe`" /Run `"$($GlobalConfig.ToolsDir)\$cfgName`""
    Write-Config "$($GlobalConfig.ToolsDir)\launch_$key.bat" $batContent
}

# 9. SUNSHINE CONFIGURATION
# ==============================================================================
Write-Host "Applying Sunshine Configuration..." -ForegroundColor Cyan

$CoverDir = "$($GlobalConfig.SunshineConfig)\covers"
if (-not (Test-Path $CoverDir)) { New-Item $CoverDir -ItemType Directory -Force | Out-Null }

foreach ($key in $Covers.Keys) {
    $dest = Join-Path $CoverDir $key
    if (-not (Test-Path $dest)) { 
        try { Invoke-WebRequest -Uri $Covers[$key] -OutFile $dest -UseBasicParsing } catch {} 
    }
}

# apps.json uses the generated launch_*.bat files
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

# sunshine.conf uses launch_setup.bat and launch_teardown.bat
$confContent = 'global_prep_cmd = [{"do":"C:\\Sunshine-Tools\\launch_setup.bat","undo":"C:\\Sunshine-Tools\\launch_teardown.bat"}]'
Write-Config "$($GlobalConfig.SunshineConfig)\sunshine.conf" $confContent

Write-Host "Host setup complete. Restart Sunshine Service to apply changes." -ForegroundColor Green
```
