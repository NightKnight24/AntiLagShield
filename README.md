# iPad Jailbreak & Anti-Lag Shield Pro (Project: ipad-jb)

Comprehensive repository and documentation for the jailbroken **iPad 6th Gen (`iPad7,6`)** running **iPadOS 17.7.11** (palera1n rootless).

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

## 🌐 Network Topology & Threat Mitigation

| Role | IP Address | MAC Address | Interface | Status / Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Router (Virgin Media Hub 5)** | `192.168.0.1` | `b0:1f:f4:01:5c:60` | `en0` (Wi-Fi) | Hardware Gateway locked via static ARP on `en0` |
| **iPad 6th Gen** | `192.168.0.217` | `f6:43:94:f4:c5:e9` | `en0` (Wi-Fi) | Protected by Anti-Lag Shield Pro v3.5 |
| **Raspberry Pi (Hostile LAN Node)** | `192.168.0.75` | `d8:3a:dd:cc:42:1c` | `en0` (Wi-Fi) | Static isolated ARP lock; ICMP redirects blocked |

---

## 🛡️ Anti-Lag Shield Pro v3.5 Architecture (Wi-Fi & Battery Edition)

Anti-Lag Shield Pro v3.5 is tailored specifically for the hardware characteristics of the iPad 6th Gen:
* **Tailored for Pure Wi-Fi:** Removed all desktop LAN/USB-Ethernet checks (`en5`, `1 Gbps LAN`, bus speed probes). Everything operates over `en0` with Broadcom WMM QoS fast-path and AWDL micro-stutter suppression.
* **Tailored for Retina Display (Non-4K):** Replaced heavy 16MB/32MB 4K buffers with optimal 6MB dynamic TCP buffers (`autorcvbufmax=6291456`, `recvspace=4194304`, `somaxconn=512`), eliminating memory pressure and power consumption while delivering flawless 1080p/2K Retina 60fps streaming.
* **Apple Battery Drain & Planned Obsolescence Defense:** Halts 9 heavy Apple background telemetry, analytics, experimentation, and inference daemons designed for newer M-series/A16 chips that constantly wake up the A10 SoC and drain the battery.

---

### 🔋 Battery Extender & Telemetry Defense

Older iOS devices on iOS 17 suffer severe battery drain primarily because of unneeded background daemons constantly querying flash storage and waking the CPU cores. Anti-Lag Shield v3.5 disables the 9 worst offenders:

| Unloaded Background Daemon | Purpose & Battery Impact Stopped |
| :--- | :--- |
| `com.apple.tipsd` | Tips suggestion daemon (periodic background wakeups) |
| `com.apple.tailspind` | Automated system stack tracing and tailspin recording |
| `com.apple.spindump` | CPU spike sampling and trace report generation |
| `com.apple.triald` | Apple A/B experimentation agent downloading tests in background |
| `com.apple.ap.adprivacyd` | Apple targeted advertising and behavioral tracking |
| `com.apple.parsec-fbf` | CoreParsec telemetry feedback uploads |
| `com.apple.siriinferenced` | On-device machine learning inference (runs without NPU on A10) |
| `com.apple.duetexpertd` | CoreDuet predictive habit learning |
| `com.apple.coreduetd` | CoreDuet app activity and context logging |

#### Additional Power Optimizations
1. **Darwin CPU Timer Coalescing (`kern.timer.coalescing_enabled=1`):** Coalesces timer interrupts across CPU cores so the A10 chip stays in deep C-state sleep longer.
2. **Display Sleep Preservation:** Screen dims and sleeps naturally when untouched; display power isn't held awake unnecessarily.
3. **Storage I/O Contention Throttling:** Renices `corespotlightd`, `knowledgeconstructiond`, and `deleted` to low priority (`nice 15`).

---

### 🚀 Core Performance & Network Defenses

1. **Stremio Web Server VIP (Port 11470):**
   * Real-time monitoring of active streams on port 11470 via `netstat -an`.
   * Automatically prioritizes `Stremio`, `NodeMobile`, `node`, `stremio-runtime`, `stremio-service`, `ffmpeg`, and `mediaserverd` with `nice -20`.
2. **TSO Anti-Bufferbloat Control:**
   * **Gaming Mode (`tso=0`):** Disables TCP segmentation offloading on the Darwin kernel to eliminate packet queuing jitter and micro-stutters.
   * **Streaming Mode (`tso=1`):** Enables hardware TSO offload for maximum burst throughput.
3. **Dual Hardware Static ARP Lock:**
   * Permanent ARP binding for Virgin Media Hub 5 gateway (`b0:1f:f4:01:5c:60`) on `en0`.
   * Isolates Raspberry Pi (`d8:3a:dd:cc:42:1c` / `192.168.0.75`).
4. **Wi-Fi Stealth & Anti-Reconnaissance:**
   * `net.inet.tcp.blackhole=2` & `net.inet.udp.blackhole=1`.
   * `net.inet.icmp.drop_redirect=1` & `net.inet.ip.redirect=0`.
5. **Broadcom Wi-Fi WMM / DSCP VIP QoS:**
   * Activates fast-path Wi-Fi QoS (`net.qos.policy.wifi_enabled=1`, `net.qos.reset_dscp_to_wifi_ac_map=1`).
6. **AWDL / AirDrop Radio Sleep:**
   * Pauses `awdl0` and `llw0` to eliminate 100ms periodic channel-hopping Wi-Fi stutters.
7. **RAM Cache Purge (+500 MB Free Memory):**
   * Reclaims inactive file cache pages via `/var/jb/usr/bin/purge`.
8. **24/7 Always-On Daemon (LaunchDaemon):**
   * Can run continuously in the background across reboots via `/var/jb/Library/LaunchDaemons/com.jordan.antilagshield.plist`.

---

## 🛠️ CLI Management Commands

All commands can be executed directly from Mac terminal over Wi-Fi:

```bash
# Check shield status
ssh ipad "/var/jb/usr/bin/shield_ctl status"

# Check battery saver status (shows daemons unloaded)
ssh ipad "/var/jb/usr/bin/shield_ctl battery status"

# Check Stremio Web Server active stream count (Port 11470)
ssh ipad "/var/jb/usr/bin/shield_ctl stremio_status"

# Launch Interactive Live Telemetry HUD (with battery %, Hub 5 ping & throughput)
ssh ipad "/var/jb/usr/bin/shield.sh"

# Purge inactive RAM (+500 MB instant reclaim)
ssh ipad "/var/jb/usr/bin/shield_ctl purge"

# Enable 24/7 Persistent Daemon (survives app exit & reboots)
ssh ipad "sudo /var/jb/usr/bin/shield_ctl daemon enable streaming"

# Disable 24/7 Persistent Daemon (returns to Multitask App Switcher mode)
ssh ipad "sudo /var/jb/usr/bin/shield_ctl daemon disable"

# Check active ARP table
ssh ipad "/var/jb/usr/sbin/arp -an"
```

---

## 🏗️ Building and Deploying Anti-Lag Shield

From within this project directory:

```bash
cd AntiLagShield
./build.sh
```
