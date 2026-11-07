#!/bin/sh
set -e

if [ -x /var/jb/usr/bin/shield_ctl ]; then
    CTL="/var/jb/usr/bin/shield_ctl"
elif [ -x /usr/bin/shield_ctl ]; then
    CTL="/usr/bin/shield_ctl"
else
    echo "Error: shield_ctl is not installed." >&2
    exit 1
fi

if [ $# -gt 0 ]; then
    exec "$CTL" "$@"
fi

echo "Anti-Lag Shield v1.0.0 — CLI Menu"
echo "---------------------------------"
"$CTL" status
echo ""
echo "  1) Start Streaming Profile (live telemetry)"
echo "  2) Start Gaming Profile (live telemetry)"
echo "  3) Apply Streaming Profile (background-free)"
echo "  4) Apply Gaming Profile (background-free)"
echo "  5) Stop & Restore Stock Defaults"
echo "  6) Clear Diagnostic Logs & Expired Caches"
echo "  7) Toggle Turbo UI"
echo ""
printf "Select [1-7]: "
read -r choice

case "$choice" in
    1) exec "$CTL" run streaming ;;
    2) exec "$CTL" run gaming ;;
    3) exec "$CTL" start streaming ;;
    4) exec "$CTL" start gaming ;;
    5) exec "$CTL" stop ;;
    6) exec "$CTL" clean ;;
    7)
        if [ "$("$CTL" turbo status)" = "TURBO_ACTIVE" ]; then
            exec "$CTL" turbo disable
        else
            exec "$CTL" turbo enable
        fi
        ;;
    *)
        echo "Cancelled."
        exit 0
        ;;
esac
