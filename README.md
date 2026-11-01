# iPad Jailbreak & Anti-Lag Shield Pro (Project: ipad-jb)

Comprehensive repository and documentation for the jailbroken **iPad 6th Gen (`iPad7,6`)** running **iPadOS 17.7.11** (palera1n rootless).

---

## 📱 Hardware & Environment Specifications

* **Device:** Apple iPad 6th Generation (Wi-Fi + Cellular, `iPad7,6`)
* **SoC:** Apple A10 Fusion (4-core, PowerVR Series7XT Plus GPU)
* **RAM:** 2 GB LPDDR4
* **Operating System:** iPadOS 17.7.11 (Build 21H324)
* **Jailbreak:** palera1n Rootless (`/var/jb` Procursus bootstrap)
* **Package Managers:** Sileo, Zebra, TrollStore Lite
* **Wireless SSH:** Configured via Wi-Fi (`ssh ipad` / `192.168.0.217` on port 22)
* **Sudoers Config:** Passwordless non-interactive root in `/var/jb/etc/sudoers.d/shield`

---

## 🌐 Network Topology & Threat Mitigation

| Role | IP Address | MAC Address | Status / Notes |
| :--- | :--- | :--- | :--- |
| **Router (Virgin Media Hub 5)** | `192.168.0.1` | `b0:1f:f4:01:5c:60` | Hardware Gateway locked via static ARP on `en0` |
| **iPad 6th Gen** | `192.168.0.217` | `f6:43:94:f4:c5:e9` | Protected by Anti-Lag Shield Pro v3.4 |
| **Raspberry Pi (Hostile LAN Node)** | `192.168.0.75` | `d8:3a:dd:cc:42:1c` | Static isolated ARP lock; ICMP redirects blocked |

---

## 🛡️ Anti-Lag Shield Pro v3.4 Architecture

Anti-Lag Shield Pro is a native low-level defense, streaming boost, and latency optimization suite consisting of a UIKit dashboard (`AntiLagShield.app`), a command-line controller (`/var/jb/usr/bin/shield_ctl`), and an interactive terminal telemetry HUD (`/var/jb/usr/bin/shield.sh`).

### Core Features (Ported from macOS v3.4)

1. **Stremio Web Server Engine VIP (Port 11470):**
   * Real-time monitoring of active 4K streaming sockets on port 11470 via `netstat -an`.
   * Automatically prioritizes `Stremio`, `NodeMobile`, `node`, `stremio-runtime`, `stremio-service`, `ffmpeg`, and `mediaserverd` with `nice -20`.
   * Displayed live on both the UIKit Dashboard and interactive terminal HUD.

2. **TSO (TCP Segmentation Offload) & Anti-Bufferbloat Control:**
   * **Gaming Mode (`tso=0`):** Disables TCP segmentation offloading on the Darwin kernel to eliminate packet aggregation queuing and micro-jitter spikes.
   * **Streaming Mode (`tso=1`):** Enables hardware TSO offload for full Gigabit burst throughput and smooth 4K pre-buffering.

3. **Socket Connection Queue Tuning (`kern.ipc.somaxconn`):**
   * Scaled from stock `128` up to `512` (Gaming) and `1024` (Streaming) to prevent socket dropouts during concurrent connections.

4. **DNS Resolver Cache Flush & Reset:**
   * Executes `sudo killall -HUP mDNSResponder` upon starting or toggling modes to flush cached DNS and ensure 0ms resolver latency.

5. **Display & Wi-Fi Keep-Awake Shield (iOS Caffeinate):**
   * Uses `[UIApplication sharedApplication].idleTimerDisabled = YES;` in UIKit to prevent screen dimming, idle sleep, and Wi-Fi radio power-save dropouts during long gaming or streaming sessions.

6. **Storage I/O Contention & Background Indexing Throttling:**
   * Throttles background daemons (`corespotlightd`, `knowledgeconstructiond`, `deleted`, `cloudphotod`) to low priority (`nice 15`), ensuring flash storage and CPU are dedicated to media and gaming.

7. **Dual Hardware Static ARP Lock & Pi Defense:**
   * Enforces permanent kernel ARP bindings for both the default router and the Raspberry Pi on interface `en0`.
   * Watchdog automatically re-locks gateway ARP if poisoned or dropped by rogue network devices.

8. **LAN Stealth & Anti-Reconnaissance:**
   * `net.inet.tcp.blackhole=2`: Drops TCP SYN packets to closed ports without sending RST.
   * `net.inet.udp.blackhole=1`: Drops unsolicited UDP packets without sending ICMP Port Unreachable.
   * `net.inet.icmp.drop_redirect=1` & `net.inet.ip.redirect=0`: Blocks ICMP redirect manipulation.

9. **Broadcom Wi-Fi WMM / DSCP VIP QoS:**
   * Activates fast-path Wi-Fi QoS (`net.qos.policy.wifi_enabled=1`, `net.qos.reset_dscp_to_wifi_ac_map=1`) ensuring media/gaming packets receive WMM Voice/Video wireless queue priority.

10. **AWDL / AirDrop Micro-Stutter Suppression:**
    * Temporarily pauses `awdl0` and `llw0` interfaces during active sessions, eliminating 100ms wireless channel hops and periodic micro-stutters.

11. **RAM Cache Purge (+500 MB Free Memory):**
    * Cleans inactive file cache pages via `/var/jb/usr/bin/purge`, reclaiming 500+ MB of RAM to prevent iOS Jetsam out-of-memory app terminations.

12. **24/7 Always-On Daemon (Optional LaunchDaemon):**
    * **Multitask Mode (Default):** Runs while `AntiLagShield` is in the App Switcher; reverts to stock iOS defaults when swiped away.
    * **24/7 Daemon Mode:** Managed via toggle in the UI or CLI (`shield_ctl daemon enable`); installs `/var/jb/Library/LaunchDaemons/com.jordan.antilagshield.plist` to run continuously across reboots.

---

## 🛠️ CLI Management Commands

All commands can be executed directly from Mac terminal over Wi-Fi:

```bash
# Check shield status
ssh ipad "/var/jb/usr/bin/shield_ctl status"

# Check Stremio Web Server active connections (Port 11470)
ssh ipad "/var/jb/usr/bin/shield_ctl stremio_status"

# Launch Interactive Live Telemetry HUD (matching Mac anti_lag_shield.command)
ssh ipad "/var/jb/usr/bin/shield.sh"

# Purge inactive RAM (+500 MB instant reclaim)
ssh ipad "/var/jb/usr/bin/shield_ctl purge"

# Enable 24/7 Persistent Daemon (survives app exit & reboots)
ssh ipad "sudo /var/jb/usr/bin/shield_ctl daemon enable streaming"

# Disable 24/7 Persistent Daemon (returns to Multitask App Switcher mode)
ssh ipad "sudo /var/jb/usr/bin/shield_ctl daemon disable"

# Check active ARP table
ssh ipad "/var/jb/usr/sbin/arp -an"

# Inspect active process priorities
ssh ipad "/bin/ps -A -o pid,nice,comm | grep -iE 'mediaserverd|stremio|prime|youtube|roblox'"
```

---

## 🏗️ Building and Deploying Anti-Lag Shield

From within this project directory:

```bash
cd AntiLagShield
./build.sh
```

The build script compiles `main.m` with the iOS SDK, transfers the Mach-O binary and `shield_ctl` to the iPad, signs them using `ldid -S`, and refreshes the SpringBoard icon cache via `uicache`.
