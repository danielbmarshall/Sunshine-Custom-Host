````markdown
# ☀️ Sunshine Custom Host (Windows 11)

> **The "Bulletproof" Cloud Gaming Host.**
> *Automated deployment of a hardened, self-healing, and topology-aware Sunshine server for Windows 11.*

---

## 📖 Overview
Setting up a headless game streaming server on Windows 11 is often plagued by "Black Screen" issues, permission errors (Exit Code 5), and multi-monitor chaos. 

**Sunshine-Custom-Host** is a "One-Click" solution that installs and configures a highly customized Sunshine environment designed to solve these specific problems. It replaces fragile batch files with robust, error-handling PowerShell automation and bypasses Windows security restrictions using legitimate system tools.

---

## 🚀 Quick Start
**Prerequisites:** Windows 11 (Admin Rights)

Open **PowerShell** as Administrator and run this single command:

```powershell
irm [https://raw.githubusercontent.com/danielbmarshall/Sunshine-Custom-Host/main/install.ps1](https://raw.githubusercontent.com/danielbmarshall/Sunshine-Custom-Host/main/install.ps1) | iex
````

### 📦 What this script does automatically:

1.  **Installs Core Software:** Checks for and installs **Sunshine**, **Playnite**, and the **Virtual Display Driver** (IddSampleDriver) if missing.
2.  **Deploys Tools:** Downloads `MultiMonitorTool`, `AdvancedRun`, and `WindowsDisplayManager` into a hardened directory (`C:\Sunshine-Tools`).
3.  **Configures Automation:** Generates custom Setup/Teardown scripts that manage your monitors intelligently.
4.  **Updates Sunshine:** Overwrites your `apps.json` and `sunshine.conf` with a pre-configured "Smorgasbord" of apps.

-----

## ✨ Key Features

### 🛡️ 1. "Error 5" Bypass (Secure App Launching)

Standard Sunshine setups often crash with `Access Denied` or `Invalid Argument` errors when launching apps like Steam or Playnite.

  * **Our Solution:** We use [AdvancedRun](https://www.nirsoft.net/utils/advanced_run.html) to handle process elevation.
  * **Result:** Sunshine simply triggers a clean `.cfg` file. Windows handles the complexity of launching apps as "Current User" (for Steam) or "Administrator" (for Monitor Switching) seamlessly.

### 🖥️ 2. Topology-Aware Monitor Switching

Most scripts blindly disable monitors, which causes crashes on **Daisy-Chained (MST)** setups where one monitor feeds signal to others.

  * **Our Solution:** The `setup` script analyzes your topology and disables the "Hub" monitor **last**.
  * **Race-Condition Fix:** Includes "Wait" loops to ensure the Virtual Display is fully registered by Windows PnP before attempting to switch, eliminating startup black screens.

### ❤️ 3. Self-Healing & Fail-Safe

  * **Watchdog Logic:** If the Virtual Display fails to load for *any* reason, the script immediately catches the error and force-restores your physical monitors.
  * **Teardown Enforcement:** The teardown script explicitly forces your main display back to "Primary" status, preventing windows from getting lost on ghost screens.

### 🎮 4. The "Smorgasbord" App List

Pre-configured entries for the most popular client/launchers:

  * **Steam Big Picture** (Uses Native Protocol `steam://` to avoid double-launch issues)
  * **Playnite** (Fullscreen Mode)
  * **Xbox App** (Game Pass)
  * **EmulationStation (ES-DE)**
  * **Utilities:** Remote Sleep, Remote Restart, and an **Emergency Task Manager** (High Priority) to kill frozen games.

-----

## ⚙️ Customization

### Changing Resolution / Refresh Rate

By default, the host is set to **4K (3840x2160) @ 60Hz**.
To change this, edit **Line 108** of `install.ps1` in your repository **before** running the command:

```powershell
# 1. HARDCODED TARGET (Robustness Fix)
$width = 2560; $height = 1440; $fps = 120  <-- Customize here
```

### Adding Your Own Apps

You can add new apps by editing the `$Apps` hashtable in `install.ps1`.

  * **Format:** `"cfg_filename.cfg" = "ExePath|CommandLine|StartDir|RunAs(0=User,1=Admin)|WindowState(0=Hidden,3=Max)"`

-----

## ❓ Troubleshooting

**Q: The script says "Virtual Display Driver not found" after installing?**
A: Some strict Group Policies block silent driver installation. Navigate to `C:\IddSampleDriver` and right-click `install.bat` -\> **Run as Administrator**.

**Q: My screen is stuck black\!**
A: Use the **Emergency Shortcut**:

1.  Press `Win + R` (blindly if needed).
2.  Type `shutdown /r /t 0` and hit Enter.
3.  Your physical monitors will restore automatically on reboot.

-----

## 📜 Credits

  * **Sunshine** by [LizardByte](https://app.lizardbyte.dev/)
  * **Virtual Display Driver** by [MikeTheTech](https://github.com/itsmikethetech/Virtual-Display-Driver)
  * **Utilities** by [NirSoft](https://www.nirsoft.net/) & [Patrick-the-programmer](https://github.com/patrick-theprogrammer/WindowsDisplayManager)

<!-- end list -->

````
