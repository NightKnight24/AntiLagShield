#!/var/jb/usr/bin/bash
VIRGIN_HUB_MAC="b0:1f:f4:01:5c:60"
FALLBACK_ROUTER_IP="192.168.0.1"

ACTION="$1"
MODE="${2:-streaming}"
APP_PID="$3"

case "$ACTION" in
    start)
        INTERFACE=$(/var/jb/usr/sbin/route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
        [ -z "$INTERFACE" ] && INTERFACE="en0"
        ROUTER_IP=$(/var/jb/usr/sbin/route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')
        [ -z "$ROUTER_IP" ] && ROUTER_IP="$FALLBACK_ROUTER_IP"

        # 1. ARP Lock to Virgin Media Hub
        sudo /var/jb/usr/sbin/arp -d "$ROUTER_IP" ifscope "$INTERFACE" >/dev/null 2>&1
        sudo /var/jb/usr/sbin/arp -s "$ROUTER_IP" "$VIRGIN_HUB_MAC" ifscope "$INTERFACE" >/dev/null 2>&1
        sudo /var/jb/usr/sbin/arp -s "$ROUTER_IP" "$VIRGIN_HUB_MAC" ifscope en0 >/dev/null 2>&1

        # 2. Disable AWDL/AirDrop background scans
        sudo /var/jb/usr/sbin/ifconfig awdl0 down >/dev/null 2>&1
        sudo /var/jb/usr/sbin/ifconfig llw0 down >/dev/null 2>&1

        # 3. Kernel Buffer Optimization
        if [ "$MODE" = "gaming" ]; then
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.delayed_ack=0 >/dev/null 2>&1
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.sendspace=2097152 >/dev/null 2>&1
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.recvspace=2097152 >/dev/null 2>&1
        else
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.delayed_ack=2 >/dev/null 2>&1
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autorcvbufmax=4194304 >/dev/null 2>&1
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autosndbufmax=4194304 >/dev/null 2>&1
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.recvspace=4194304 >/dev/null 2>&1
            sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.sendspace=2097152 >/dev/null 2>&1
        fi
        sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.recvspace=4194304 >/dev/null 2>&1
        sudo /var/jb/usr/sbin/sysctl -w net.inet.udp.maxdgram=65535 >/dev/null 2>&1

        mkdir -p /var/mobile/Library/Caches
        echo "ACTIVE:$MODE" > /var/mobile/Library/Caches/shield_state.txt

        # 4. Background watchdog to track App Switcher (Multitask) status
        if [ -n "$APP_PID" ] && [ "$APP_PID" -gt 1 ]; then
            pkill -f "shield_watchdog" >/dev/null 2>&1
            (
                exec -a shield_watchdog /var/jb/usr/bin/bash -c '
                    while kill -0 '$APP_PID' 2>/dev/null; do
                        sleep 1
                    done
                    /var/jb/usr/bin/shield_ctl stop
                '
            ) >/dev/null 2>&1 &
        fi
        echo "SHIELD_STARTED:$MODE"
        ;;

    stop)
        pkill -f "shield_watchdog" >/dev/null 2>&1

        # Restore stock kernel sysctls
        sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.delayed_ack=3 >/dev/null 2>&1
        sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.sendspace=131072 >/dev/null 2>&1
        sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.recvspace=131072 >/dev/null 2>&1
        sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autorcvbufmax=2097152 >/dev/null 2>&1
        sudo /var/jb/usr/sbin/sysctl -w net.inet.tcp.autosndbufmax=2097152 >/dev/null 2>&1

        # Restore AWDL (AirDrop)
        sudo /var/jb/usr/sbin/ifconfig awdl0 up >/dev/null 2>&1
        sudo /var/jb/usr/sbin/ifconfig llw0 up >/dev/null 2>&1

        rm -f /var/mobile/Library/Caches/shield_state.txt
        echo "SHIELD_STOPPED"
        ;;

    status)
        if [ -f /var/mobile/Library/Caches/shield_state.txt ]; then
            cat /var/mobile/Library/Caches/shield_state.txt
        else
            echo "INACTIVE"
        fi
        ;;

    *)
        echo "Usage: $0 {start [gaming|streaming] [pid]|stop|status}"
        exit 1
        ;;
esac
