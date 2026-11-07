# Privacy Policy for Anti-Lag Shield Pro

**Last Updated:** November 1, 2026  
**Developer:** NightKnight24  
**Project:** Anti-Lag Shield Pro (`com.nightknight.antilagshield`)  
**Repository:** [https://github.com/NightKnight24/AntiLagShield](https://github.com/NightKnight24/AntiLagShield)

---

## 1. Overview & Commitment to Zero-Data Collection
Anti-Lag Shield Pro is engineered with a strict **Zero-Data Collection & Zero-Telemetry** architecture. We believe software running with root or elevated privileges on jailbroken and TrollStore iOS/iPadOS devices must maintain absolute user privacy and device sovereignty.

Anti-Lag Shield Pro **does not collect, store, sell, or transmit any personal data, user telemetry, analytics, or browsing information.**

---

## 2. On-Device Local Processing
All performance enhancements, system health monitors, and network optimizations operate exclusively on the local device:

- **Local Network Telemetry:** When discovering the local Wi-Fi router's default gateway IP and MAC address, the operation is executed locally on Darwin's network stack via `route` and `arp`. Any optional custom gateway override is stored solely on-device in `/var/mobile/Library/Preferences/com.nightknight.antilagshield.plist` to lock kernel ARP routing. This data is never sent to any external server.
- **Latency Ping Tests:** Telemetry ping tests (`1.1.1.1` and your local gateway) measure local round-trip packet latency on demand. No identifiable payloads or user data are sent or received.
- **Flash Storage & Cache Cleaner:** When purging stale crash logs (`/var/mobile/Library/Logs/CrashReporter/`), diagnostic reports, or WebKit temporary caches, the cleanup occurs strictly on internal flash memory. No file contents, filenames, or user documents are read, copied, or transmitted.
- **Hardware Acceleration (Turbo UI):** Toggling Darwin accessibility preferences via `AccessibilityUtilities` occurs directly within the local operating system to disable SpringBoard GPU blur shaders.

---

## 3. No Third-Party Analytics or Advertisements
Anti-Lag Shield Pro contains:
- ❌ **No third-party SDKs** (No Firebase, Google Analytics, Adjust, AppsFlyer, etc.)
- ❌ **No advertising networks**
- ❌ **No tracking cookies or fingerprinting**
- ❌ **No remote logging or crash reporting daemons**

---

## 4. Open-Source Transparency
The complete source code of Anti-Lag Shield Pro is publicly auditable on GitHub:  
[https://github.com/NightKnight24/AntiLagShield](https://github.com/NightKnight24/AntiLagShield)

You can inspect all scripts (`shield_ctl`, `shield.sh`) and the compiled UIKit client (`main.m`) to verify that no network traffic leaves your device without your explicit command.

---

## 5. Contact & Questions
If you have questions regarding this Privacy Policy or wish to report a security vulnerability, please open an issue on the official GitHub repository:  
[https://github.com/NightKnight24/AntiLagShield/issues](https://github.com/NightKnight24/AntiLagShield/issues)
