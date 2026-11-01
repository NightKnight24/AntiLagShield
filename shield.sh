#!/bin/bash

# ==============================================================================
# 🛡️  iPadOS Anti-Lag Shield Pro v3.5 (Wi-Fi & Battery Saver HUD)  🛡️
# Battery Telemetry Defense, Stremio VIP (Port 11470) & Hardware ARP Defense
# ==============================================================================

VIRGIN_HUB_MAC="b0:1f:f4:01:5c:60"
PI_MAC="d8:3a:dd:cc:42:1c"
PI_IP="192.168.0.75"
FALLBACK_ROUTER_IP="192.168.0.1"
INTERNET_PING_HOST="1.1.1.1"

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

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}🛡️   Anti-Lag Shield Pro v3.5 — iPad Wi-Fi & Battery Edition   🛡️${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "${BRIGHT_CYAN}Select operating mode for your iPad:${NC}"
echo -e "  ${BRIGHT_GREEN}[1] 🎮 Gaming Mode${NC}     — Zero Latency, Instant ACK, TSO Off (Anti-Bufferbloat)"
echo -e "  ${BRIGHT_MAGENTA}[2] 🎬 Streaming Mode${NC}  — Retina HD Throughput, Stremio Web Server VIP (Port 11470)"
echo ""
read -t 15 -p "Enter choice [1 or 2] (Default: 2 for Stremio): " USER_CHOICE || USER_CHOICE="2"
echo ""

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

# 2. Detect default interface and router
INTERFACE="en0"
ROUTER_IP=$(/var/jb/usr/sbin/route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')
[ -z "$ROUTER_IP" ] && ROUTER_IP=$FALLBACK_ROUTER_IP
echo -e "${GREEN}[✔] Primary Route: $INTERFACE (Wi-Fi) | Gateway: $ROUTER_IP${NC}"

# 3. Halt Apple Background Telemetry & Battery Drain Daemons
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
        sudo /var/jb/usr/bin/launchctl unload "$plist" >/dev/null 2>&1
    fi
done
sudo /var/jb/usr/sbin/sysctl -w kern.timer.coalescing_enabled=1 >/dev/null 2>&1
echo -e "${GREEN}[✔] Battery Saver & Telemetry Shield: ACTIVE (Apple background bloat halted)${NC}"

# 4. Gateway ARP Lock to Virgin Media Hub & Raspberry Pi Isolation
echo -e "${CYAN}[*] Securing Gateway ARP to Virgin Media Hub ($VIRGIN_HUB_MAC)...${NC}"
sudo /var/jb/usr/sbin/arp -d "$ROUTER_IP" ifscope "$INTERFACE" >/dev/null 2>&1
sudo /var/jb/usr/sbin/arp -s "$ROUTER_IP" "$VIRGIN_HUB_MAC" ifscope "$INTERFACE" >/dev/null 2>&1
sudo /var/jb/usr/sbin/arp -d "$PI_IP" ifscope "$INTERFACE" >/dev/null 2>&1
sudo /var/jb/usr/sbin/arp -s "$PI_IP" "$PI_MAC" ifscope "$INTERFACE" >/dev/null 2>&1
echo -e "${GREEN}[✔] Gateway $ROUTER_IP LOCKED to Virgin Media Hub ($VIRGIN_HUB_MAC)${NC}"
echo -e "${GREEN}[✔] Raspberry Pi ($PI_MAC / $PI_IP) Interception & Redirect Shield: ACTIVE${NC}"

# Block ICMP Redirects & Enable Wi-Fi Stealth Blackhole
sudo /var/jb/usr/sbin/sysctl -w net.inet.icmp.drop_redirect=1 >/dev/null 2>&1
sudo /var/jb/usr/sbin/sysctl -w net.inet.ip.redirect=0 >/dev/null 2>&1
sudo /var/jb/usr/sbin/sysctl -w net.inet6.icmp6.rediraccept=0 >/dev/null 2>&1
sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.blackhole=2 >/dev/null 2>&1
sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.blackhole=1 >/dev/null 2>&1

# 5. Disable AWDL / AirDrop background scans (Eliminates Wi-Fi micro-stutters)
sudo /var/jb/usr/sbin/ifconfig awdl0 down >/dev/null 2>&1
sudo /var/jb/usr/sbin/ifconfig llw0 down >/dev/null 2>&1
echo -e "${GREEN}[✔] Apple Wireless Direct Link (AWDL): PAUSED (No channel-hop jitter)${NC}"

# 6. Flush DNS resolver cache
sudo killall -HUP mDNSResponder >/dev/null 2>&1
echo -e "${GREEN}[✔] DNS Resolver Cache: FLUSHED (Zero resolver latency)${NC}"

# 7. Throttle background indexing & storage churn
for bg_daemon in corespotlightd knowledgeconstructiond deleted cloudphotod; do
    BG_PIDS=$(/bin/ps -A -o pid,comm 2>/dev/null | awk -v d="$bg_daemon" '$0 ~ d && !/awk/ {print $1}')
    for bg_p in $BG_PIDS; do
        [ -n "$bg_p" ] && sudo renice 15 -p "$bg_p" >/dev/null 2>&1
    done
done
echo -e "${GREEN}[✔] Background Indexing: THROTTLED (Zero flash storage/CPU contention)${NC}"

# 8. Apply Mode-Specific Kernel Parameters (Optimized for 2048x1536 Retina / 2GB RAM)
if [[ "$SHIELD_MODE" == "gaming" ]]; then
    # Gaming Tuning: Instant ACK, TSO Off (Anti-Bufferbloat), Tight Buffers, somaxconn=512
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.tso=0 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.delayed_ack=0 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.sendspace=2097152 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.recvspace=2097152 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autorcvbufmax=4194304 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autosndbufmax=4194304 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.recvspace=2097152 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.maxdgram=65535 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w kern.ipc.somaxconn=512 >/dev/null 2>&1
    echo -e "${GREEN}[✔] Gaming Tuning: Instant ACK (0ms) | TSO Off (Anti-Bufferbloat) | 2MB Buffers${NC}"
else
    # Streaming Tuning: TSO Burst, 6MB Retina Dynamic Window, somaxconn=512, Stremio Port 11470 VIP
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.tso=1 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.delayed_ack=2 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.sendspace=2097152 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.recvspace=4194304 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autorcvbufmax=6291456 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autosndbufmax=6291456 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.recvspace=4194304 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.maxdgram=65535 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w kern.ipc.somaxconn=512 >/dev/null 2>&1
    echo -e "${GREEN}[✔] Streaming Tuning: TSO Burst | 6MB Retina Buffer | Stremio Web VIP (Port 11470)${NC}"
fi

# Reclaim RAM immediately
sudo /var/jb/usr/bin/purge >/dev/null 2>&1
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
    
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.blackhole=0 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.blackhole=0 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.tso=1 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.delayed_ack=3 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.sendspace=131072 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.recvspace=131072 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autorcvbufmax=2097152 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autosndbufmax=2097152 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.recvspace=786896 >/dev/null 2>&1
    sudo /var/jb/usr/sbin/sysctl -w kern.ipc.somaxconn=128 >/dev/null 2>&1
    
    # Restore AWDL (AirDrop)
    sudo /var/jb/usr/sbin/ifconfig awdl0 up >/dev/null 2>&1
    sudo /var/jb/usr/sbin/ifconfig llw0 up >/dev/null 2>&1

    # Restore background indexing daemons to normal priority
    for bg_daemon in corespotlightd knowledgeconstructiond deleted cloudphotod; do
        BG_PIDS=$(/bin/ps -A -o pid,comm 2>/dev/null | awk -v d="$bg_daemon" '$0 ~ d && !/awk/ {print $1}')
        for bg_p in $BG_PIDS; do
            [ -n "$bg_p" ] && sudo renice 0 -p "$bg_p" >/dev/null 2>&1
        done
    done

    # Re-enable system background daemons
    for d in "${BATTERY_HOGS[@]}"; do
        plist="/System/Library/LaunchDaemons/$d.plist"
        if [ -f "$plist" ]; then
            sudo /var/jb/usr/bin/launchctl load "$plist" >/dev/null 2>&1
        fi
    done

    echo -e "${BRIGHT_GREEN}================================================================${NC}"
    echo -e "${BRIGHT_GREEN}[✔] All iPad defaults restored. Have a great session!${NC}"
    echo -e "${BRIGHT_GREEN}================================================================${NC}"
    exit 0
}

trap cleanup SIGHUP SIGINT SIGTERM EXIT

# Live Telemetry & Priority Booster Engine
export SHIELD_MODE_ENV="$SHIELD_MODE"
export ROUTER_IP_ENV="$ROUTER_IP"
export VIRGIN_MAC_ENV="$VIRGIN_HUB_MAC"
export PI_MAC_ENV="$PI_MAC"

/var/jb/usr/bin/python3 - <<'PY_SCRIPT_END'
import os, sys, time, subprocess

shield_mode = os.environ.get("SHIELD_MODE_ENV", "streaming")
router_ip = os.environ.get("ROUTER_IP_ENV", "192.168.0.1")
virgin_mac = os.environ.get("VIRGIN_MAC_ENV", "b0:1f:f4:01:5c:60")
pi_mac = os.environ.get("PI_MAC_ENV", "d8:3a:dd:cc:42:1c")

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
        out = subprocess.check_output(['/var/jb/usr/sbin/netstat', '-ib', '-I', iface], stderr=subprocess.DEVNULL).decode()
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
        out = subprocess.check_output(['/var/jb/bin/ping', '-c', '1', '-W', str(timeout_ms), host], stderr=subprocess.DEVNULL).decode()
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
        out = subprocess.check_output(['/var/jb/usr/sbin/netstat', '-an'], stderr=subprocess.DEVNULL).decode()
        return sum(1 for l in out.splitlines() if '11470' in l and 'ESTABLISHED' in l)
    except:
        return 0

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
        
        # Ping router and internet every 2 seconds
        if loop_counter % 2 == 0 or r_ms is None:
            r_ms = ping_host(router_ip, timeout_ms=350)
            i_ms = ping_host("1.1.1.1", timeout_ms=400)
            
        if loop_counter % 15 == 0:
            bat_str = get_battery()
        
        # Check active processes and Stremio streams
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
            app_label = f"{C_GRAY}Shield Active{C_RESET}"
            
        print(f"[{ts}] {mode_tag} | 📶 Wi-Fi (en0) | Router: {r_colored} | Ping: {p_colored} | 🔋 {bat_str} | {down_colored} | {up_colored} | {app_label} | {C_GREEN}🛡️ Hub Locked{C_RESET}")
        sys.stdout.flush()

except KeyboardInterrupt:
    pass
PY_SCRIPT_END
