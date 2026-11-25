# RefreshDNS

A minimal, native macOS one-click utility to flush the system DNS cache (`dscacheutil -flushcache` + `killall -HUP mDNSResponder`) without typing `sudo` passwords every time — no menu bar clutter, no idle background memory usage.

> 极简 macOS 原生一键刷新 DNS 缓存工具：首次授权一次后永久免密运行，无菜单栏常驻、默认不占后台内存，可选休眠唤醒自动刷新，支持中 / 英 / 西三语。

## Features

- **One-Click & Passwordless**: Authorize once on first launch to install a minimal system helper (`LaunchDaemon` + XPC). Every run after that flushes DNS instantly without prompting for a password (even from standard non-admin accounts).
- **Optional Auto-Refresh on Wake**: Optionally automatically flush DNS whenever your Mac wakes from sleep via an ultra-lightweight IOKit `LaunchAgent` (no menu bar icon, no admin password needed to toggle, HUD notification on wake enabled by default and toggleable).
- **Zero Background Footprint by Default**: No menu bar icon, no Dock persistence (`LSUIElement`), and when wake auto-refresh is off, nothing stays resident in memory; the privileged helper is launched on demand by `launchd` and automatically exits after 15 seconds of inactivity.
- **Native Glass HUD Feedback**: Displays a non-activating translucent macOS HUD banner (`DNS Cache Flushed`) that never steals focus and works even under Focus / Do Not Disturb, then quits automatically.
- **Minimal Attack Surface**: The root-owned helper (`me.wanghuan.refreshdns.helper`) accepts zero shell input or arguments over XPC and only executes fixed `/usr/bin/dscacheutil -flushcache` and `/usr/bin/killall -HUP mDNSResponder`.
- **Localized (i18n)**: Automatically follows your macOS language with built-in support for **English (`en`)**, **Simplified Chinese (`zh-Hans`)**, and **Spanish (`es`)**.
- **Universal Binary**: Supports both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs on macOS 13+.

## Installation

### Option 1: Download DMG (Releases)

1. Download the latest `RefreshDNS-*.dmg` (e.g. `RefreshDNS-1.1.1.dmg`) from [Releases](https://github.com/fredwangwang/refreshdns/releases).
2. Open the DMG and drag `RefreshDNS.app` into `Applications`.
3. Launch `RefreshDNS` from Spotlight, Dock, or Finder.
   - **Note (unsigned/ad-hoc release)**: Because this release is not notarized with a paid Apple Developer ID, macOS Gatekeeper may block the first launch. If that happens, run:
     ```bash
     xattr -cr /Applications/RefreshDNS.app
     ```
     and open it again.

### Option 2: Build from Source

Requires macOS 13+ with Xcode Command Line Tools (`swiftc`).

```bash
git clone https://github.com/fredwangwang/refreshdns.git
cd refreshdns
make install
```

To package a DMG locally:

```bash
make dmg
```

## Usage

- **First run**: Open `RefreshDNS.app` → approve the one-time macOS administrator prompt to install `/Library/PrivilegedHelperTools/me.wanghuan.refreshdns.helper` and `/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist` (optionally check *"Auto-refresh DNS when waking from sleep"*) → DNS cache is flushed immediately.
- **Every run after**: Launch `RefreshDNS.app` (via Spotlight, Raycast, Dock, or Finder) → instant DNS flush → HUD confirmation → auto-exit.
- **Options & Wake Auto-Refresh**: Hold **`Option (⌥)`** while opening `RefreshDNS.app` (or run `--settings`) to open the **Options** window, where you can:
  - Toggle **Auto-refresh DNS on wake from sleep**
  - Toggle **Show HUD notification on wake refresh** (enabled by default; disable for silent background refreshes)
  - Trigger an immediate DNS flush or uninstall RefreshDNS
- **CLI options**:
  ```bash
  /Applications/RefreshDNS.app/Contents/MacOS/RefreshDNS --settings      # Open Options window
  /Applications/RefreshDNS.app/Contents/MacOS/RefreshDNS --wake-on       # Enable auto-refresh on wake
  /Applications/RefreshDNS.app/Contents/MacOS/RefreshDNS --wake-off      # Disable auto-refresh on wake
  /Applications/RefreshDNS.app/Contents/MacOS/RefreshDNS --wake-hud-on   # Show HUD on wake refresh
  /Applications/RefreshDNS.app/Contents/MacOS/RefreshDNS --wake-hud-off  # Silent wake refresh (no HUD)
  /Applications/RefreshDNS.app/Contents/MacOS/RefreshDNS --wake-status   # Show current wake settings
  ```

## Uninstall

Choose any of the following methods to cleanly remove the `LaunchDaemon`, wake `LaunchAgent` (if enabled), privileged helper, preferences, and `RefreshDNS.app`:

1. **Built-in one-click uninstall (no Terminal needed)**: Hold the **`Option (⌥)`** key while opening `RefreshDNS.app`, then click **Uninstall...** and confirm in the dialog.
2. **CLI uninstall flag**:
   ```bash
   /Applications/RefreshDNS.app/Contents/MacOS/RefreshDNS --uninstall
   ```
3. **Bundled uninstall script inside the `.app`**:
   ```bash
   /Applications/RefreshDNS.app/Contents/Resources/uninstall.sh
   ```
4. **From source directory**:
   ```bash
   make uninstall
   ```

## Architecture

```text
RefreshDNS.app (me.wanghuan.refreshdns)
  ├─ One-click flush ──► NSXPCConnection (.privileged) ──► launchd (MachService: me.wanghuan.refreshdns.helper)
  │                                                          └─ on-demand root helper (exits after 15s idle)
  │                                                               ├─ /usr/bin/dscacheutil -flushcache
  │                                                               └─ /usr/bin/killall -HUP mDNSResponder
  └─ Optional Wake Listener (LaunchAgent: me.wanghuan.refreshdns.wakeagent)
       └─ IOKit IORegisterForSystemPower (kIOMessageSystemHasPoweredOn)
            ├─ HUD enabled  ──► RefreshDNS --wake-flush (XPC flush + HUD)
            └─ HUD disabled ──► direct XPC flushDNS (silent)
```

## License

[MIT](LICENSE)
