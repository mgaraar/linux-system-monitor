#!/bin/bash

# Linux System Monitor
# digunakan untuk melihat informasi sistem yang berjalan

LOG_DIR="$HOME/linux-lab"
LOG_FILE="$LOG_DIR/monitor.log"

CPU_THRESHOLD=80
RAM_THRESHOLD=80
DISK_THRESHOLD=80

mkdir -p "$LOG_DIR"

# Tampilkan output dan simpan ke log
exec > >(tee -a "$LOG_FILE") 2>&1

HOST=$(hostname)
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# Ambil sampel CPU
CPU_USAGE=$(
    LC_ALL=C top -bn2 -d 1 |
    grep 'Cpu(s)' |
    tail -n 1 |
    awk -F',' '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /id/) {
                gsub(/[^0-9.]/, "", $i)
                printf "%.0f", 100-$i
                exit
            }
        }
    }'
)

# Hitung RAM terpakai berdasarkan RAM available
RAM_USAGE=$(
    free -b |
    awk '/Mem:/ {
        if ($2 > 0)
            printf "%.0f", (($2-$7)/$2)*100
    }'
)

# Ambil penggunaan disk root
DISK_USAGE=$(
    df -P / |
    awk 'NR==2 {
        gsub(/%/, "", $5)
        print $5
    }'
)

echo ""
echo "================================"
echo "    INFORMASI SISTEM"
echo "================================"
echo "Waktu    : $CURRENT_TIME"
echo "Hostname : $HOST"

echo ""
echo "--- STATUS SUMBER DAYA ---"

check_metric() {
    NAME="$1"
    VALUE="$2"
    LIMIT="$3"

    if [[ ! "$VALUE" =~ ^[0-9]+$ ]]; then
        echo "$NAME: ERROR - data tidak tersedia"
    elif (( VALUE >= LIMIT )); then
        echo "$NAME: WARNING - ${VALUE}%"
    else
        echo "$NAME: NORMAL - ${VALUE}%"
    fi
}

check_service() {
    local SERVICE="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "$SERVICE: systemctl tidak tersedia"
        return
    fi

    local LOAD_STATE
    local ACTIVE_STATE

    LOAD_STATE=$(systemctl show "$SERVICE" \
        --property=LoadState --value 2>/dev/null)

    ACTIVE_STATE=$(systemctl show "$SERVICE" \
        --property=ActiveState --value 2>/dev/null)

    if [[ "$LOAD_STATE" == "not-found" || -z "$LOAD_STATE" ]]; then
        echo "$SERVICE: NOT FOUND atau status tidak dapat dibaca"
    elif [[ "$ACTIVE_STATE" == "active" ]]; then
        echo "$SERVICE: ACTIVE"
    else
        echo "$SERVICE: NOT ACTIVE ($ACTIVE_STATE)"
    fi
}


check_metric "CPU" "$CPU_USAGE" "$CPU_THRESHOLD"
check_metric "RAM" "$RAM_USAGE" "$RAM_THRESHOLD"
check_metric "DISK" "$DISK_USAGE" "$DISK_THRESHOLD"

echo ""
echo "--- DETAIL MEMORI ---"
free -h

echo ""
echo "--- DETAIL DISK ---"
df -h /

echo ""
echo "--- PEMERIKSAAN SERVICE ---"
check_service "ssh.service"

echo ""
echo "================================"
echo "Prabowo anjing, pemerintah kontol"
