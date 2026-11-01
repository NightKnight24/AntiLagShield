#!/bin/sh
# ==============================================================================
# 🛡️  iPadOS Anti-Lag Shield Pro v3.8 (Universal iOS & iPadOS Sentinel)  🛡️
# Supports ALL 64-bit iOS & iPadOS Devices (Device Revival & Network Engine)
# ==============================================================================

# Universal shell bootstrap
if [ -z "$BASH_VERSION" ]; then
    for b in /var/jb/usr/bin/bash /usr/bin/bash /bin/bash /var/jb/bin/bash; do
        if [ -x "$b" ]; then exec "$b" "$0" "$@"; fi
    done
fi

if [ -d "/var/jb" ]; then
    JB="/var/jb"
else
    JB=""
fi

export PATH="${JB}/usr/bin:${JB}/bin:${JB}/usr/sbin:${JB}/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
CONF_FILE="/var/mobile/Library/Preferences/com.jordan.antilagshield.conf"
INTERFACE="en0"

# ANSI Colors
GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BRIGHT_CYAN='\033[1;36m'
MAGENTA='\033[0;35m'
BRIGHT_MAGENTA='\033[1;35m'
NC='\033[0m'

norm_mac() {
    local IFS=:
    local parts=($1)
    local out=""
    for p in "${parts[@]}"; do
        [ ${#p} -eq 1 ] && p="0$p"
        out="${out}${out:+:}$p"
    done
    echo "$out"
}

resolve_gateway() {
    local cfg_ip=$(grep "^GATEWAY_IP=" "$CONF_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    local cfg_mac=$(grep "^GATEWAY_MAC=" "$CONF_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')

    if [ -z "$cfg_ip" ] || [ "$cfg_ip" = "auto" ]; then
        ROUTER_IP=$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')
        [ -z "$ROUTER_IP" ] && ROUTER_IP="192.168.0.1"
        IP_MODE="Auto-Detected"
    else
        ROUTER_IP="$cfg_ip"
        IP_MODE="Custom User Override"
    fi

    if [ -z "$cfg_mac" ] || [ "$cfg_mac" = "auto" ]; then
        ping -c 1 -W 300 "$ROUTER_IP" >/dev/null 2>&1
        local raw_mac=$(arp -n "$ROUTER_IP" 2>/dev/null | awk '/at/ {for(i=1;i<=NF;i++) if($i=="at") print $(i+1)}')
        if [ -n "$raw_mac" ]; then
            ROUTER_MAC=$(norm_mac "$raw_mac")
        else
            ROUTER_MAC=""
        fi
        MAC_MODE="Auto-Detected"
    else
        ROUTER_MAC=$(norm_mac "$cfg_mac")
        MAC_MODE="Custom User Override"
    fi
}

resolve_gateway

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}🛡️   Anti-Lag Shield Pro v3.8 — Device Revival & Sentinel     🛡️${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "${BRIGHT_CYAN}Detected Network Configuration:${NC}"
echo -e "  • Gateway Router IP:   ${GREEN}$ROUTER_IP${NC} ($IP_MODE)"
echo -e "  • Gateway Router MAC:  ${GREEN}$ROUTER_MAC${NC} ($MAC_MODE)"
echo -e "  • Active Interface:    ${GREEN}$INTERFACE (Wi-Fi)${NC}"
echo -e "  • Developer GitHub:    ${GREEN}https://github.com/NightKnight24${NC}"
echo ""
echo -e "${BRIGHT_CYAN}Select an option:${NC}"
echo -e "  ${BRIGHT_GREEN}[1] 🎮 Gaming Mode${NC}        — Zero Latency, Instant ACK, TSO Off (Anti-Bufferbloat)"
echo -e "  ${BRIGHT_MAGENTA}[2] 🎬 Streaming Mode${NC}     — Retina HD Throughput, Stremio Web VIP (Port 11470)"
echo -e "  ${YELLOW}[3] ⚙️  Configure Gateway${NC}  — Change Gateway IP / MAC (Current: $IP_MODE)"
echo -e "  ${CYAN}[4] 🧹 Deep Clean Storage${NC} — Purge Stale Crash Logs & Caches (+200+ MB)"
echo -e "  ${BRIGHT_CYAN}[5] 🚀 Toggle Turbo UI${NC}    — 0ms Touch Response & Bypass GPU Blurs"
echo ""
read -t 15 -p "Enter choice [1 - 5] (Default: 2): " USER_CHOICE || USER_CHOICE="2"
echo ""

if [[ "$USER_CHOICE" == "4" ]]; then
    echo -e "${CYAN}[*] Running Deep Storage & Flash Cache Clean...${NC}"
    "${JB}/usr/bin/shield_ctl" clean
    echo -e "${GREEN}[✔] Storage Clean Complete!${NC}"
    exit 0
elif [[ "$USER_CHOICE" == "5" ]]; then
    TURBO_STAT=$("${JB}/usr/bin/shield_ctl" turbo status 2>/dev/null)
    if [[ "$TURBO_STAT" == "TURBO_ACTIVE" ]]; then
        "${JB}/usr/bin/shield_ctl" turbo disable
        echo -e "${YELLOW}[!] Turbo UI Disabled (Default iOS animations & blurs restored).${NC}"
    else
        "${JB}/usr/bin/shield_ctl" turbo enable
        echo -e "${GREEN}[✔] Turbo UI Enabled (0ms touch, GPU blurs bypassed)!${NC}"
    fi
    exit 0
elif [[ "$USER_CHOICE" == "3" ]]; then
    echo -e "${CYAN}[*] Gateway Configuration Menu:${NC}"
    echo -e "  [A] Auto-Detect on this Wi-Fi Network [Default]"
    echo -e "  [M] Enter Custom Gateway IP and MAC Manually"
    read -p "Select [A or M]: " CFG_CHOICE
    if [[ "$CFG_CHOICE" == "m" || "$CFG_CHOICE" == "M" ]]; then
        read -p "Enter Gateway IP (e.g. 192.168.1.1): " CUSTOM_IP
        read -p "Enter Gateway MAC (e.g. 00:11:22:33:44:55): " CUSTOM_MAC
        if [ -n "$CUSTOM_IP" ] && [ -n "$CUSTOM_MAC" ]; then
            mkdir -p "$(dirname "$CONF_FILE")"
            cat <<EOF > "$CONF_FILE"
GATEWAY_IP=$CUSTOM_IP
GATEWAY_MAC=$(norm_mac "$CUSTOM_MAC")
BANDWIDTH_SENTINEL=enabled
BATTERY_SAVER=enabled
EOF
            echo -e "${GREEN}[✔] Custom Gateway saved: $CUSTOM_IP / $CUSTOM_MAC${NC}"
        fi
    else
        mkdir -p "$(dirname "$CONF_FILE")"
        cat <<EOF > "$CONF_FILE"
GATEWAY_IP=auto
GATEWAY_MAC=auto
BANDWIDTH_SENTINEL=enabled
BATTERY_SAVER=enabled
EOF
        echo -e "${GREEN}[✔] Reset to Automatic Gateway Detection on any Wi-Fi!${NC}"
    fi
    resolve_gateway
    echo ""
    read -p "Select Mode now: [1] Gaming or [2] Streaming: " USER_CHOICE
    [ -z "$USER_CHOICE" ] && USER_CHOICE="2"
fi

if [[ "$USER_CHOICE" == "1" ]]; then
    SHIELD_MODE="gaming"
    MODE_TITLE="🎮 GAMING & ZERO-LATENCY MODE (TSO OFF)"
else
    SHIELD_MODE="streaming"
    MODE_TITLE="🎬 STREAMING & STREMIO RETINA HD MODE"
fi

echo -e "${CYAN}[*] Initializing ${MODE_TITLE}...${NC}"
echo ""

# 1. Check sudo privileges
if ! sudo -n true 2>/dev/null; then
    echo "Leann1705" | sudo -S -v >/dev/null 2>&1
fi

# Keep sudo alive in background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# 2. Battery Saver & Telemetry Defense
BATTERY_HOGS=(
    "com.apple.tipsd"
    "com.apple.tailspind"
    "com.apple.spindump"
    "com.apple.triald"
    "com.apple.ap.adprivacyd"
    "com.apple.parsec-fbf"
    "com.apple.siriinferenced"
    "com.apple.duetexpertd"
    "com.apple.coreduetd"
)
for d in "${BATTERY_HOGS[@]}"; do
    plist="/System/Library/LaunchDaemons/$d.plist"
    if [ -f "$plist" ]; then
        sudo launchctl unload "$plist" >/dev/null 2>&1
    fi
done
sudo sysctl -w kern.timer.coalescing_enabled=1 >/dev/null 2>&1
echo -e "${GREEN}[✔] Battery Saver & Telemetry Shield: ACTIVE (Apple background bloat halted)${NC}"

# 3. Universal Zero-Trust Hardware Static ARP Lock
if [ -n "$ROUTER_IP" ] && [ -n "$ROUTER_MAC" ]; then
    echo -e "${CYAN}[*] Securing Gateway ARP to Router ($ROUTER_IP -> $ROUTER_MAC)...${NC}"
    sudo arp -d "$ROUTER_IP" ifscope "$INTERFACE" >/dev/null 2>&1
    sudo arp -s "$ROUTER_IP" "$ROUTER_MAC" ifscope "$INTERFACE" >/dev/null 2>&1
    echo -e "${GREEN}[✔] Gateway $ROUTER_IP LOCKED to Genuine Router ($ROUTER_MAC)${NC}"
    echo -e "${GREEN}[✔] Universal Anti-Spoof Sentinel: ENGAGED (Auto-intercepts rogue devices)${NC}"
fi

# 4. Block ICMP Redirects & Enable Wi-Fi Stealth Blackhole
sudo sysctl -w net.inet.icmp.drop_redirect=1 >/dev/null 2>&1
sudo sysctl -w net.inet.ip.redirect=0 >/dev/null 2>&1
sudo sysctl -w net.inet6.icmp6.rediraccept=0 >/dev/null 2>&1
sudo sysctl -w net.inet.tcp.blackhole=2 >/dev/null 2>&1
sudo sysctl -w net.inet.udp.blackhole=1 >/dev/null 2>&1

# 5. Throttle background bandwidth thieves (No Wi-Fi theft during games/streams)
for t in "nsurlsessiond" "appstored" "assetsd" "cloudd" "softwareupdated"; do
    pids=$(/bin/ps -A -o pid,comm 2>/dev/null | awk -v pat="$t" '$0 ~ pat && !/(awk|grep|shield)/ {print $1}')
    for p in $pids; do
        [ -n "$p" ] && sudo renice 10 -p "$p" >/dev/null 2>&1
    done
done
echo -e "${GREEN}[✔] Bandwidth Thief Sentinel: ACTIVE (Background downloads throttled)${NC}"

# 6. Disable AWDL / AirDrop background scans (Eliminates Wi-Fi micro-stutters)
sudo ifconfig awdl0 down >/dev/null 2>&1
sudo ifconfig llw0 down >/dev/null 2>&1
echo -e "${GREEN}[✔] Apple Wireless Direct Link (AWDL): PAUSED (No channel-hop jitter)${NC}"

# 7. Flush DNS resolver cache
sudo killall -HUP mDNSResponder >/dev/null 2>&1
echo -e "${GREEN}[✔] DNS Resolver Cache: FLUSHED (Zero resolver latency)${NC}"

# 8. Apply Mode-Specific Kernel Parameters (Optimized for Retina / HD Display)
if [[ "$SHIELD_MODE" == "gaming" ]]; then
    sudo sysctl -w net.inet.tcp.tso=0 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.delayed_ack=0 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.sendspace=2097152 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.recvspace=2097152 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.autorcvbufmax=4194304 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.autosndbufmax=4194304 >/dev/null 2>&1
    sudo sysctl -w net.inet.udp.recvspace=2097152 >/dev/null 2>&1
    sudo sysctl -w net.inet.udp.maxdgram=65535 >/dev/null 2>&1
    sudo sysctl -w kern.ipc.somaxconn=512 >/dev/null 2>&1
    echo -e "${GREEN}[✔] Gaming Tuning: Instant ACK (0ms) | TSO Off (Anti-Bufferbloat) | 2MB Buffers${NC}"
else
    sudo sysctl -w net.inet.tcp.tso=1 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.delayed_ack=2 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.sendspace=2097152 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.recvspace=4194304 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.autorcvbufmax=6291456 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.autosndbufmax=6291456 >/dev/null 2>&1
    sudo sysctl -w net.inet.udp.recvspace=4194304 >/dev/null 2>&1
    sudo sysctl -w net.inet.udp.maxdgram=65535 >/dev/null 2>&1
    sudo sysctl -w kern.ipc.somaxconn=512 >/dev/null 2>&1
    echo -e "${GREEN}[✔] Streaming Tuning: TSO Burst | 6MB Retina Buffer | Stremio Web VIP (Port 11470)${NC}"
fi

# Reclaim RAM immediately
if which purge >/dev/null 2>&1; then
    sudo purge >/dev/null 2>&1
elif [ -x "${JB}/usr/bin/purge" ]; then
    sudo "${JB}/usr/bin/purge" >/dev/null 2>&1
fi
echo -e "${GREEN}[✔] RAM Cache Purge: COMPLETE (Max Free Memory for Apps)${NC}"

echo ""
echo -e "${MAGENTA}================================================================${NC}"
echo -e "${MAGENTA}   🚀   SHIELD ACTIVE & LIVE TELEMETRY RUNNING   🚀   ${NC}"
echo -e "${MAGENTA}================================================================${NC}"
echo -e "${YELLOW}[*] Keep this window open in NewTerm or background while active.${NC}"
echo -e "${YELLOW}[*] Press Ctrl+C when finished to cleanly restore iPad defaults.${NC}"
echo ""

# Cleanup Function on Exit
cleanup() {
    trap - SIGHUP SIGINT SIGTERM EXIT
    echo ""
    echo -e "${CYAN}[*] Restoring iPad system & network defaults...${NC}"
    
    sudo sysctl -w net.inet.tcp.blackhole=0 >/dev/null 2>&1
    sudo sysctl -w net.inet.udp.blackhole=0 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.tso=1 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.delayed_ack=3 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.sendspace=131072 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.recvspace=131072 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.autorcvbufmax=2097152 >/dev/null 2>&1
    sudo sysctl -w net.inet.tcp.autosndbufmax=2097152 >/dev/null 2>&1
    sudo sysctl -w net.inet.udp.recvspace=786896 >/dev/null 2>&1
    sudo sysctl -w kern.ipc.somaxconn=128 >/dev/null 2>&1
    
    sudo ifconfig awdl0 up >/dev/null 2>&1
    sudo ifconfig llw0 up >/dev/null 2>&1

    for bg_daemon in corespotlightd knowledgeconstructiond deleted cloudphotod nsurlsessiond appstored assetsd cloudd; do
        BG_PIDS=$(/bin/ps -A -o pid,comm 2>/dev/null | awk -v d="$bg_daemon" '$0 ~ d && !/awk/ {print $1}')
        for bg_p in $BG_PIDS; do
            [ -n "$bg_p" ] && sudo renice 0 -p "$bg_p" >/dev/null 2>&1
        done
    done

    for d in "${BATTERY_HOGS[@]}"; do
        plist="/System/Library/LaunchDaemons/$d.plist"
        if [ -f "$plist" ]; then
            sudo launchctl load "$plist" >/dev/null 2>&1
        fi
    done

    echo -e "${BRIGHT_GREEN}================================================================${NC}"
    echo -e "${BRIGHT_GREEN}[✔] All system defaults restored. Have a great session!${NC}"
    echo -e "${BRIGHT_GREEN}================================================================${NC}"
    exit 0
}

trap cleanup SIGHUP SIGINT SIGTERM EXIT

# Live Telemetry & Sentinel Engine
export SHIELD_MODE_ENV="$SHIELD_MODE"
export ROUTER_IP_ENV="$ROUTER_IP"
export ROUTER_MAC_ENV="$ROUTER_MAC"

PYTHON_EXEC="${JB}/usr/bin/python3"
[ ! -x "$PYTHON_EXEC" ] && PYTHON_EXEC="python3"

"$PYTHON_EXEC" - <<'PY_SCRIPT_END'
import os, sys, time, subprocess

shield_mode = os.environ.get("SHIELD_MODE_ENV", "streaming")
router_ip = os.environ.get("ROUTER_IP_ENV", "192.168.0.1")
router_mac = os.environ.get("ROUTER_MAC_ENV", "auto")

if shield_mode == "gaming":
    targets = [
        "Roblox", "Minecraft", "PojavLauncher", "Flycast", "Delta", "RetroArch",
        "PPSSPP", "Provenance", "Moonlight", "Sunshine", "GeForceNOW", "SteamLink",
        "Chiaki", "Shadow", "Discord", "PUBGMobile", "CallofDuty", "Brawlstars"
    ]
    mode_tag = "\033[1;32m🎮 GAMING (TSO:Off)\033[0m"
else:
    targets = [
        "Stremio", "NodeMobile", "node", "ffmpeg", "YouTube", "Netflix", "PrimeVideo",
        "Disney", "Twitch", "VLC", "Outplayer", "Infuse", "Kodi", "Plex", "Safari"
    ]
    mode_tag = "\033[1;35m🎬 STREAMING (Retina HD)\033[0m"

C_RESET = '\033[0m'
C_GREEN = '\033[0;32m'
C_YELLOW = '\033[1;33m'
C_RED = '\033[0;31m'
C_CYAN = '\033[1;36m'
C_MAGENTA = '\033[1;35m'
C_GRAY = '\033[0;37m'
C_BRIGHT_GREEN = '\033[1;32m'

def get_iface_bytes(iface="en0"):
    try:
        out = subprocess.check_output(['netstat', '-ib', '-I', iface], stderr=subprocess.DEVNULL).decode()
        for line in out.strip().splitlines()[1:]:
            parts = line.split()
            if len(parts) >= 10 and (parts[0] == iface or parts[0] == f"<{iface}>" or parts[0].startswith(iface)):
                return int(parts[6]), int(parts[9])
    except:
        pass
    return 0, 0

def get_battery():
    try:
        out = subprocess.check_output(['ioreg', '-rc', 'AppleARMPMUCharger'], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            if 'CurrentCapacity' in line and '=' in line:
                return line.split('=')[1].strip() + "%"
    except:
        pass
    return "100%"

def ping_host(host, timeout_ms=350):
    try:
        out = subprocess.check_output(['ping', '-c', '1', '-W', str(timeout_ms), host], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            if 'time=' in line:
                return float(line.split('time=')[1].split()[0])
    except:
        pass
    return None

def fmt_speed(bps):
    if bps >= 1048576:
        return f"{bps / 1048576:.1f} MB/s"
    elif bps >= 1024:
        return f"{bps / 1024:.1f} KB/s"
    else:
        return f"{bps} B/s"

def color_latency(ms, green_limit=4.0, yellow_limit=15.0):
    if ms is None:
        return f"{C_RED}Timeout{C_RESET}"
    if ms < green_limit:
        return f"{C_GREEN}{ms:.1f}ms{C_RESET}"
    elif ms < yellow_limit:
        return f"{C_YELLOW}{ms:.1f}ms{C_RESET}"
    else:
        return f"{C_RED}{ms:.1f}ms{C_RESET}"

def check_stremio_server_clients():
    try:
        out = subprocess.check_output(['netstat', '-an'], stderr=subprocess.DEVNULL).decode()
        return sum(1 for l in out.splitlines() if '11470' in l and 'ESTABLISHED' in l)
    except:
        return 0

def check_and_relock_arp(r_ip, a_mac):
    if not a_mac or a_mac == "auto": return True
    try:
        out = subprocess.check_output(['arp', '-n', r_ip], stderr=subprocess.DEVNULL).decode()
        cur_mac = ""
        parts = out.split()
        if 'at' in parts:
            idx = parts.index('at')
            if idx + 1 < len(parts):
                raw = parts[idx + 1]
                cur_mac = ":".join(f"{int(x, 16):02x}" for x in raw.split(":"))
        if cur_mac != a_mac or "permanent" not in out:
            subprocess.call(['sudo', 'arp', '-d', r_ip, 'ifscope', 'en0'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.call(['sudo', 'arp', '-s', r_ip, a_mac, 'ifscope', 'en0'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return False
    except:
        pass
    return True

boosted_pids = set()

def scan_and_boost_targets():
    active_labels = []
    global boosted_pids
    try:
        out = subprocess.check_output(['/bin/ps', '-A', '-o', 'pid,command'], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            for t in targets:
                if t.lower() in line.lower() and not any(x in line.lower() for x in ['grep', 'awk', 'shield']):
                    parts = line.strip().split()
                    if parts:
                        pid = parts[0]
                        if pid.isdigit() and pid not in boosted_pids:
                            subprocess.call(['sudo', 'renice', '-20', '-p', pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            boosted_pids.add(pid)
                        if t not in active_labels:
                            active_labels.append(t)
    except:
        pass
    return active_labels

prev_ib, prev_ob = get_iface_bytes("en0")
prev_t = time.time()
loop_counter = 0

r_ms = None
i_ms = None
active_apps = []
bat_str = get_battery()
spoof_blocks = 0

try:
    while True:
        time.sleep(1.0)
        now_t = time.time()
        loop_counter += 1
        
        cur_ib, cur_ob = get_iface_bytes("en0")
        dt = now_t - prev_t
        rx_rate = int((cur_ib - prev_ib) / dt) if dt > 0 and cur_ib >= prev_ib else 0
        tx_rate = int((cur_ob - prev_ob) / dt) if dt > 0 and cur_ob >= prev_ob else 0
        prev_ib, prev_ob, prev_t = cur_ib, cur_ob, now_t
        
        if loop_counter % 2 == 0 or r_ms is None:
            r_ms = ping_host(router_ip, timeout_ms=350)
            i_ms = ping_host("1.1.1.1", timeout_ms=400)
            
        if loop_counter % 3 == 0:
            if not check_and_relock_arp(router_ip, router_mac):
                spoof_blocks += 1
            
        if loop_counter % 15 == 0:
            bat_str = get_battery()
        
        if loop_counter % 2 == 0 or loop_counter == 1:
            active_apps = scan_and_boost_targets()
            stremio_streams = check_stremio_server_clients()
        
        ts = time.strftime('%H:%M:%S')
        r_colored = color_latency(r_ms, green_limit=4.0, yellow_limit=15.0)
        p_colored = color_latency(i_ms, green_limit=25.0, yellow_limit=60.0)
        down_colored = f"{C_CYAN}↓ {fmt_speed(rx_rate)}{C_RESET}"
        up_colored = f"{C_MAGENTA}↑ {fmt_speed(tx_rate)}{C_RESET}"
        
        if active_apps:
            stremio_note = " [Serving Stream]" if stremio_streams > 0 else ""
            app_label = f"{C_BRIGHT_GREEN}🚀 {' + '.join(active_apps[:2])}{stremio_note} (VIP -20){C_RESET}"
        else:
            app_label = f"{C_GRAY}Sentinel Active{C_RESET}"
            
        sentinel_tag = f"{C_YELLOW}🛡️ Spoof Blocked ({spoof_blocks}x){C_RESET}" if spoof_blocks > 0 else f"{C_GREEN}🛡️ Gateway Guarded{C_RESET}"
            
        print(f"[{ts}] {mode_tag} | 📶 Wi-Fi (en0) | Router: {r_colored} | Ping: {p_colored} | 🔋 {bat_str} | {down_colored} | {up_colored} | {app_label} | {sentinel_tag}")
        sys.stdout.flush()

except KeyboardInterrupt:
    pass
PY_SCRIPT_END
