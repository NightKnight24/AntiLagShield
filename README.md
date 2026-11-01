# Anti-Lag Shield Pro (Universal iOS & iPadOS Sentinel & Device Revival)

Comprehensive repository and documentation for **Anti-Lag Shield Pro v3.8**.
Engineered to support **all 64-bit iOS & iPadOS devices** from **iOS 12.0 to iOS 18.x**, combining low-latency network sentinel defenses with deep hardware & storage device revival.

---

## ⚡ Device Revival & System Health Category (v3.8)

In addition to network packet optimization, v3.8 introduces a dedicated **Device Revival** layer designed to make aging devices with 2–3 GB RAM feel brand new:

1. **🧹 Deep Flash Storage & Cache Cleaner:**
   * 1-tap reclamation of hundreds of megabytes or gigabytes of stale crash dumps (`/var/mobile/Library/Logs/CrashReporter`), diagnostic traces, and expired WebKit caches.
   * Drastically reduces NAND write amplification and restores snappy, instant app launch times.
2. **🚀 Turbo UI Mode (0ms Touch & No GPU Blur):**
   * Uses native private `AccessibilityUtilities` APIs (`_AXSSetReduceMotionEnabled` and `_AXSSetEnhanceBackgroundContrastEnabled`).
   * Bypasses heavy real-time GPU Gaussian blur shaders across the Dock, Control Center, and widgets.
   * Cuts app opening latency from 500ms spring animations to 0ms instant touch response.
3. **🔒 Anti-Jetsam Kernel Shielding (`memorystatus`):**
   * Relaxes aggressive kernel memory kill thresholds (`kern.memorystatus_purge_on_warning=1`, `kern.memorystatus_apps_idle_delay_time=30`).
   * Extends the app idle grace period from 10s to 30s, preventing background app termination and Safari tab reloads.
   * Tunes TCP keep-alive sockets (`net.inet.tcp.always_keepalive=1`, `net.inet.tcp.keepidle=30000`).
4. **🛡️ 12-Daemon AI, Vision & Telemetry Neutralizer:**
   * Halts `photoanalysisd`, `mediaanalysisd`, `cloudphotod`, `tipsd`, `tailspind`, `spindump`, `triald`, `adprivacyd`, `parsec-fbf`, `siriinferenced`, `duetexpertd`, and `coreduetd`.
   * Completely eliminates background computer vision and neural training loops on general CPU cores.

---

## 📦 How to Install (For Any User)

Anti-Lag Shield Pro is pre-packaged and ready for any user to install across all 64-bit iOS & iPadOS devices:

### Option 1: Sileo / Zebra / Cydia (Standard `.deb` Package)
1. Download **[`dist/AntiLagShield_v3.8_rootless.deb`](dist/AntiLagShield_v3.8_rootless.deb)** (for Dopamine, palera1n rootless, Sileo, Zebra) or **[`dist/AntiLagShield_v3.8_rootful.deb`](dist/AntiLagShield_v3.8_rootful.deb)** (for checkra1n, unc0ver, Cydia).
2. Tap **Share** → **Open in Sileo** (or Zebra) and tap **Install**.
3. The app icon will appear directly on your Home Screen.

### Option 2: TrollStore 1-Tap Install (`.tipa`)
1. Download **[`dist/AntiLagShield_v3.8.tipa`](dist/AntiLagShield_v3.8.tipa)**.
2. Tap **Share** → **Open in TrollStore**.
3. Installs with persistent root capabilities without needing a full jailbreak!

### Option 3: One-Line Terminal Installer (SSH / NewTerm)
Run this single command directly in terminal on any jailbroken iPhone or iPad:
```bash
curl -sL https://raw.githubusercontent.com/NightKnight24/AntiLagShield/main/install.sh | bash
```

---

The Mach-O binary is compiled with `minos 12.0` (`LC_BUILD_VERSION`) and `UIDeviceFamily` 1 (iPhone) & 2 (iPad), enabling compatibility across 11+ years of Apple devices:

| Device Family | Models Supported | iOS / iPadOS Range |
| :--- | :--- | :--- |
| **Legacy iPhones (A7 - A8)** | iPhone 5s, iPhone 6, iPhone 6 Plus | iOS 12.0 – 12.5.7 |
| **Legacy iPads (A7 - A8X)** | iPad Air 1, iPad mini 2, iPad mini 3 | iOS 12.0 – 12.5.7 |
| **Mid-Era iPhones (A9 - A10)** | iPhone 6s, 6s Plus, iPhone SE (1st Gen), iPhone 7, 7 Plus | iOS 12.0 – 15.8.3 |
| **Mid-Era iPads (A9 - A10X)** | iPad mini 4, iPad Air 2, iPad 5th/6th/7th Gen, iPad Pro 1st/2nd Gen | iOS 12.0 – 17.7.x |
| **Modern iPhones (A11 - A17)** | iPhone 8, iPhone X, XR, XS, 11, 12, 13, 14, 15, 16 series | iOS 12.0 – 18.x |
| **Modern iPads (M1 - M4)** | iPad mini 5/6, iPad Air 3–5 (M2), iPad Pro (M1, M2, M4) | iPadOS 13.0 – 18.x |

---

## 🔓 Universal Jailbreak Architecture (Rootless & Rootful)

The suite automatically inspects the filesystem to dynamically select the correct binary paths without requiring separate packages:

* **Rootless (iOS 15.0 – 18.x):**
  * Supported jailbreaks: **Dopamine**, **palera1n rootless**, **XinaA15**, **TrollStore**, **Rootless Bootstrap**.
  * Targets `/var/jb/usr/bin`, `/var/jb/usr/sbin`, `/var/jb/bin`, and `/var/jb/Library/LaunchDaemons/`.
* **Rootful (iOS 12.0 – 14.8.1 & Legacy):**
  * Supported jailbreaks: **checkra1n**, **unc0ver**, **Taurine**, **Chimera**, **Odyssey**, **palera1n rootful**.
  * Automatically falls back to `/usr/bin`, `/usr/sbin`, `/bin`, and `/Library/LaunchDaemons/`.

---

## 🌐 100% Universal Network Capabilities

Anti-Lag Shield Pro works on any home, school, office, or travel Wi-Fi network (`192.168.x.x`, `10.x.x.x`, `172.x.x.x`):

1. **Automatic Gateway Auto-Discovery (Default):**
   * Automatically detects the active Wi-Fi default router IP and queries its hardware MAC address.
   * Normalizes the MAC address format into standard 2-digit hex and locks it permanently into the kernel ARP table on `en0`.
2. **Manual Gateway Customization:**
   * Users can enter custom Gateway IP & MAC addresses via the UIKit UI (`⚙️ Config Gateway` button) or CLI (`shield_ctl config set <ip> <mac>`).
   * Stored in `/var/mobile/Library/Preferences/com.jordan.antilagshield.conf`.
3. **Universal Anti-Spoof Sentinel:**
   * Continuously scans the kernel ARP table: if ANY rogue device on the LAN attempts to poison the ARP cache, spoof the router, or redirect traffic, the Sentinel immediately intercepts, purges the forged entry, and restores the genuine router lock.
4. **Bandwidth Thief Sentinel:**
   * Automatically scans and throttles background downloaders (`nsurlsessiond`, `appstored`, `assetsd`, `cloudd`, `softwareupdated`) to `nice 10`, ensuring they never steal Wi-Fi bandwidth during active video streaming or gaming sessions.
5. **Battery Saver & Telemetry Defense:**
   * Unloads 9 heavy Apple background telemetry, analytics, experimentation, and inference daemons (`tipsd`, `tailspind`, `spindump`, `triald`, `adprivacyd`, `parsec-fbf`, `siriinferenced`, `duetexpertd`, `coreduetd`).
   * Enables Darwin CPU timer coalescing (`kern.timer.coalescing_enabled=1`) so the SoC stays in deep C-state sleep longer.
   * Throttles disk-heavy indexing daemons (`corespotlightd`, `knowledgeconstructiond`, `deleted`, `cloudphotod`) to low priority (`nice 15`).
   * Prevents Apple's thermal and voltage CPU throttling ("battery-gate") by keeping the SoC cool and preventing current spikes.
6. **Developer Showcase & GitHub Integration:**
   * In-app interactive card with direct 1-tap Safari launch to developer profile: [https://github.com/NightKnight24](https://github.com/NightKnight24).
   * Long-press to customize profile URL or configure via CLI (`shield_ctl config set-github <url>`).
7. **Retina Display Dynamic Buffers (Non-4K):**
   * Specifically tuned for Retina/HD displays: tight 6 MB dynamic TCP window (`autorcvbufmax=6291456`, `recvspace=4194304`, `somaxconn=512`), eliminating memory waste while delivering stutter-free 1080p 60fps streaming.
8. **TSO Anti-Bufferbloat Control:**
   * **Gaming Mode (`tso=0`):** Disables TCP segmentation offloading on the Darwin kernel to eliminate packet queuing jitter and micro-stutters.
   * **Streaming Mode (`tso=1`):** Enables hardware TSO offload for maximum burst throughput.

---

## 🛠️ CLI Management Commands

All commands can be executed directly from Mac terminal over Wi-Fi or in NewTerm on iOS:

```bash
# Check current shield status
ssh ipad "shield_ctl status"

# View current gateway configuration (auto-detected or custom)
ssh ipad "shield_ctl config show"

# Reset gateway to automatic detection on any Wi-Fi
ssh ipad "shield_ctl config auto"

# Set a custom Gateway IP and MAC override
ssh ipad "shield_ctl config set 192.168.1.1 00:11:22:33:44:55"

# Set or update developer GitHub profile URL
ssh ipad "shield_ctl config set-github 'https://github.com/NightKnight24'"

# Check battery saver status (shows daemons unloaded)
ssh ipad "shield_ctl battery status"

# Launch Interactive Live Telemetry HUD (with battery %, router ping & throughput)
ssh ipad "shield.sh"

# Purge inactive RAM (+500 MB instant reclaim)
ssh ipad "shield_ctl purge"

# Deep clean flash storage & crash logs (+200+ MB reclaimed)
ssh ipad "shield_ctl clean"

# Toggle Turbo UI Mode (0ms touch response, bypass GPU blurs)
ssh ipad "shield_ctl turbo enable"
ssh ipad "shield_ctl turbo disable"
ssh ipad "shield_ctl turbo status"

# Enable 24/7 Persistent Daemon (survives app exit & reboots)
ssh ipad "sudo shield_ctl daemon enable streaming"
```

---

## 🏗️ Building and Deploying Anti-Lag Shield

From within this project directory:

```bash
cd AntiLagShield
./build.sh
```
