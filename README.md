

---

## 🚀 Quick Start

**Prerequisites:** Windows 11 (Administrator Rights)

Open **PowerShell 7 (`pwsh`)** (or Windows PowerShell) as Administrator and run:

```powershell
irm https://raw.githubusercontent.com/danielbmarshall/Sunshine-Custom-Host/main/install.ps1 | iex
````

> **What happens next?**
> The script will automatically download dependencies, install drivers, configure the firewall, and restart Sunshine. You will be ready to stream in about 60 seconds.

-----

## ✨ Key Features

### 🛡️ "Error 5" Bypass (Secure App Launching)

Standard Sunshine setups crash with `Access Denied` or `Invalid Argument` errors when launching Admin tasks or Apps (like Steam).

  * **The Fix:** We utilize [AdvancedRun](https://www.nirsoft.net/utils/advanced_run.html) to precisely control process elevation.
  * **Result:** Sunshine triggers a clean config file. Windows handles the complexity of launching Steam as "User" and Monitor Scripts as "Admin" seamlessly.

### 🖥️ Topology-Aware Monitor Switching

Daisy-chained (MST) monitors often crash when disabled in the wrong order (e.g., disabling the hub before the satellite).

  * **The Fix:** Our custom `setup` script analyzes your topology and specifically disables the **Hub Monitor** last.
  * **Race-Condition Free:** Includes "Wait" loops to ensure the Virtual Display is fully registered by Windows PnP before attempting to switch, eliminating startup black screens.

### ❤️ Self-Healing Architecture

  * **Watchdog Logic:** If the Virtual Display fails to load for *any* reason, the script automatically detects the failure and force-restores your physical monitors instantly.
  * **Teardown Enforcement:** The teardown script explicitly forces your main display back to "Primary" status, preventing windows from getting lost on ghost screens.

### 🎮 The "Smorgasbord" App List

Includes pre-configured, secure launchers for:

  * **Steam Big Picture** (Uses Native Protocol `steam://` to avoid double-launch issues)
  * **Playnite** (Fullscreen Mode)
  * **Xbox App** (Game Pass)
  * **EmulationStation** (ES-DE)
  * **Utilities:** Remote Sleep, Remote Restart, and an **Emergency Task Manager** (High Priority) to kill frozen games.

### 🤫 Quiet + QoL Installer Defaults

  * Sunshine installs via winget with quiet overrides to suppress "already installed" prompts.
  * AutoHideMouseCursor is deployed to `C:\Sunshine-Tools` and added to Startup.
  * VDM setup/teardown scripts log every MultiMonitorTool call for easier troubleshooting.

-----

## ⚙️ Customization

### Changing Virtual Display Resolution

By default the virtual display is **4K (3840x2160) @ 60Hz**. To change it, edit the `$ClientWidth/$ClientHeight/$ClientFps/$ClientHdr` defaults in `install.ps1` (near the top of the script where virtual display IDs are set) before running.

Example (1440p @ 120Hz):

```powershell
$ClientWidth = 2560
$ClientHeight = 1440
$ClientFps = 120
```

### Adding New Apps

You can add new games or apps by editing the `$Apps` list in `install.ps1`.

  * **Format:** `"cfg_name.cfg" = "ExePath|Args|Dir|RunAs(0=User,1=Admin)|Window(0=Hidden,3=Max)"`

-----

## 🔧 Under the Hood

\<details\>
\<summary\>\<b\>Click to see the installed toolchain\</b\>\</summary\>
<br>

The installer creates a hardened directory at `C:\Sunshine-Tools` containing:

| Tool | Purpose | Source |
| :--- | :--- | :--- |
| **AdvancedRun** | Bypass Sunshine permission blocks. | [NirSoft](https://www.nirsoft.net/utils/advanced_run.html) |
| **MultiMonitorTool** | Save/Restore layouts & switch inputs. | [NirSoft](https://www.nirsoft.net/utils/multi_monitor_tool.html) |
| **AutoHideMouseCursor** | Auto-hide the cursor on startup. | [SoftwareOK](https://www.softwareok.com/?seite=Freeware/AutoHideMouseCursor) |
| **WindowsDisplayManager** | Precise resolution/HDR control module. | [Patrick-the-programmer](https://github.com/patrick-theprogrammer/WindowsDisplayManager) |
| **Virtual Display Driver** | Creates a headless 4K/HDR dummy plug in software. | [MikeTheTech](https://github.com/itsmikethetech/Virtual-Display-Driver) |

\</details\>

-----

## ❓ Troubleshooting

\<details\>
\<summary\>\<b\>Script says "Virtual Display Driver not found" after install?\</b\>\</summary\>
<br>
Some Group Policies block silent driver installation.

1.  Navigate to `C:\IddSampleDriver`.
2.  Right-click `install.bat` and select **Run as Administrator**.

\</details\>

\<details\>
\<summary\>\<b\>My screen is stuck black\!\</b\>\</summary\>
<br>
Use the **Emergency Shortcut**:

1.  Press `Win + R` (blindly if needed).
2.  Type `shutdown /r /t 0` and hit Enter.
3.  Your physical monitors will restore automatically on reboot.

\</details\>

-----

## 📜 Credits

  * **Sunshine** by [LizardByte](https://app.lizardbyte.dev/)
  * **Virtual Display Driver** by [MikeTheTech](https://github.com/itsmikethetech/Virtual-Display-Driver)
  * **Utilities** by [NirSoft](https://www.nirsoft.net/)

<!-- end list -->

```
```
