# RefreshDNS

A minimal, native macOS one-click utility to flush the system DNS cache (`dscacheutil -flushcache` + `killall -HUP mDNSResponder`) without typing `sudo` passwords every time — no menu bar clutter, no idle background memory usage.

> 极简 macOS 原生一键刷新 DNS 缓存工具：首次授权一次后永久免密运行，无菜单栏常驻、不占后台内存，支持中 / 英 / 西三语。

## Features

- **One-Click & Passwordless**: Authorize once on first launch to install a minimal system helper (`LaunchDaemon` + XPC). Every run after that flushes DNS instantly without prompting for a password (even from standard non-admin accounts).
- **Zero Background Footprint**: No menu bar icon, no Dock persistence (`LSUIElement`), and the helper is launched on demand by `launchd` and automatically exits after 15 seconds of inactivity.
- **Native Glass HUD Feedback**: Displays a non-activating translucent macOS HUD banner (`DNS Cache Flushed`) that never steals focus and works even under Focus / Do Not Disturb, then quits automatically.
- **Minimal Attack Surface**: The root-owned helper (`me.wanghuan.refreshdns.helper`) accepts zero shell input or arguments over XPC and only executes fixed `/usr/bin/dscacheutil -flushcache` and `/usr/bin/killall -HUP mDNSResponder`.
- **Localized (i18n)**: Automatically follows your macOS language with built-in support for **English (`en`)**, **Simplified Chinese (`zh-Hans`)**, and **Spanish (`es`)**.
- **Universal Binary**: Supports both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs on macOS 13+.

## Installation

### Option 1: Download DMG (Releases)

1. Download `RefreshDNS-1.0.0.dmg` from [Releases](https://github.com/fredwangwang/refreshdns/releases).
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

- **First run**: Open `RefreshDNS.app` → approve the one-time macOS administrator prompt to install `/Library/PrivilegedHelperTools/me.wanghuan.refreshdns.helper` and `/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist` → DNS cache is flushed immediately.
- **Every run after**: Launch `RefreshDNS.app` (via Spotlight, Raycast, Dock, or Finder) → instant DNS flush → HUD confirmation → auto-exit.

## Uninstall

Choose any of the following methods to cleanly remove the `LaunchDaemon`, privileged helper, and `RefreshDNS.app`:

1. **Built-in one-click uninstall (no Terminal needed)**: Hold the **`Option (⌥)`** key while opening `RefreshDNS.app` and confirm in the dialog.
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
  └─ NSXPCConnection (.privileged) ──► launchd (MachService: me.wanghuan.refreshdns.helper)
                                          └─ on-demand root helper (exits after 15s idle)
                                               ├─ /usr/bin/dscacheutil -flushcache
                                               └─ /usr/bin/killall -HUP mDNSResponder
```

## License

[MIT](LICENSE)
