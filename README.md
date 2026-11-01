# iPad Jailbreak & Anti-Lag Shield Pro (Universal Network Sentinel)

Comprehensive repository and documentation for the jailbroken **iPad 6th Gen (`iPad7,6`)** running **iPadOS 17.7.11** (palera1n rootless). Compatible with **any** jailbroken iPad / iPhone on **any** Wi-Fi network.

---

## 📱 Hardware & Environment Specifications

* **Device:** Apple iPad 6th Generation (Wi-Fi + Cellular, `iPad7,6`)
* **SoC:** Apple A10 Fusion (4-core, PowerVR Series7XT Plus GPU)
* **RAM:** 2 GB LPDDR4
* **Display:** 9.7" Retina IPS LCD (2048 x 1536 native resolution, 264 ppi, 60Hz)
* **Battery:** 8,827 mAh (32.9 Wh) Li-Ion • 90.5% Health (362 cycles)
* **Operating System:** iPadOS 17.7.11 (Build 21H324)
* **Jailbreak:** palera1n Rootless (`/var/jb` Procursus bootstrap)
* **Package Managers:** Sileo, Zebra, TrollStore Lite
* **Wireless SSH:** Configured via Wi-Fi (`ssh ipad` / `192.168.0.217` on port 22)
* **Sudoers Config:** Passwordless non-interactive root in `/var/jb/etc/sudoers.d/shield`

---

## 🌐 100% Universal Architecture

Anti-Lag Shield Pro v3.6 is 100% universal and works seamlessly on any home, office, school, or travel Wi-Fi network (`192.168.x.x`, `10.x.x.x`, `172.x.x.x`):

1. **Automatic Gateway Auto-Discovery (Default):**
   * Automatically detects the active Wi-Fi default router IP and queries its hardware MAC address.
   * Normalizes the MAC address format into standard 2-digit hex and locks it permanently into the kernel ARP table on `en0`.
2. **Manual Gateway Customization:**
   * Users can enter custom Gateway IP & MAC addresses via the UIKit UI (`⚙️ Config Gateway` button) or CLI (`shield_ctl config set <ip> <mac>`).
   * Stored in `/var/mobile/Library/Preferences/com.jordan.antilagshield.conf`.
3. **Universal Anti-Spoof Sentinel:**
   * Replaced the specific Raspberry Pi defense with a universal network watchdog.
   * Continuously scans the kernel ARP table: if ANY rogue device on the LAN attempts to poison the ARP cache, spoof the router, or redirect traffic, the Sentinel immediately intercepts, purges the forged entry, and restores the genuine router lock.
4. **Bandwidth Thief Sentinel:**
   * Automatically scans and throttles background downloaders (`nsurlsessiond`, `appstored`, `assetsd`, `cloudd`, `softwareupdated`) to `nice 10`, ensuring they never steal Wi-Fi bandwidth during active video streaming or gaming sessions.
5. **Battery Saver & Telemetry Defense:**
   * Unloads 9 heavy Apple background telemetry, analytics, experimentation, and inference daemons (`tipsd`, `tailspind`, `spindump`, `triald`, `adprivacyd`, `parsec-fbf`, `siriinferenced`, `duetexpertd`, `coreduetd`).
   * Enables Darwin CPU timer coalescing (`kern.timer.coalescing_enabled=1`) so the A10 SoC stays in deep C-state sleep longer.
6. **Retina Display Dynamic Buffers (Non-4K):**
   * Specifically tuned for 2048x1536 Retina displays on 2GB RAM: tight 6 MB dynamic TCP window (`autorcvbufmax=6291456`, `recvspace=4194304`, `somaxconn=512`), eliminating memory waste while delivering stutter-free 1080p 60fps streaming.
7. **TSO Anti-Bufferbloat Control:**
   * **Gaming Mode (`tso=0`):** Disables TCP segmentation offloading on the Darwin kernel to eliminate packet queuing jitter and micro-stutters.
   * **Streaming Mode (`tso=1`):** Enables hardware TSO offload for maximum burst throughput.

---

## 🛠️ CLI Management Commands

All commands can be executed directly from Mac terminal over Wi-Fi or in NewTerm on iPad:

```bash
# Check current shield status
ssh ipad "/var/jb/usr/bin/shield_ctl status"

# View current gateway configuration (auto-detected or custom)
ssh ipad "/var/jb/usr/bin/shield_ctl config show"

# Reset gateway to automatic detection on any Wi-Fi
ssh ipad "/var/jb/usr/bin/shield_ctl config auto"

# Set a custom Gateway IP and MAC override
ssh ipad "/var/jb/usr/bin/shield_ctl config set 192.168.1.1 00:11:22:33:44:55"

# Check battery saver status (shows daemons unloaded)
ssh ipad "/var/jb/usr/bin/shield_ctl battery status"

# Launch Interactive Live Telemetry HUD (with battery %, Hub 5 ping & throughput)
ssh ipad "/var/jb/usr/bin/shield.sh"

# Purge inactive RAM (+500 MB instant reclaim)
ssh ipad "/var/jb/usr/bin/shield_ctl purge"

# Enable 24/7 Persistent Daemon (survives app exit & reboots)
ssh ipad "sudo /var/jb/usr/bin/shield_ctl daemon enable streaming"
```

---

## 🏗️ Building and Deploying Anti-Lag Shield

From within this project directory:

```bash
cd AntiLagShield
./build.sh
```
