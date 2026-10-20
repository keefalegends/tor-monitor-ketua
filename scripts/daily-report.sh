#!/usr/bin/env bash
# daily-report.sh — kirim laporan harian ke Telegram (uptime, RAM, disk, container).
# Jadwalkan via cron: 0 7 * * * (setiap hari jam 07.00)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: file .env tidak ditemukan" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

BOT_TOKEN="${BOT_TOKEN:?Set BOT_TOKEN di .env}"
CHAT_ID="${CHAT_ID:?Set CHAT_ID di .env}"

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "parse_mode=HTML" \
        > /dev/null
}

HOSTNAME_VAL=$(hostname)
DATE_STR=$(date '+%Y-%m-%d %H:%M WIB')

UPTIME_STR=$(uptime -p)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)

MEM_TOTAL=$(grep MemTotal     /proc/meminfo | awk '{printf "%.0f MB", $2/1024}')
MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{printf "%.0f MB", $2/1024}')
SWAP_USED=$(free -m | awk '/^Swap:/ {printf "%d MB", $3}')

DISK_INFO=$(df -h / | awk 'NR==2 {printf "%s dari %s (terpakai %s)", $3, $2, $5}')

if command -v docker &> /dev/null; then
    CONTAINER_COUNT=$(docker ps -q | wc -l)
    CONTAINER_LIST=$(docker ps --format '  • {{.Names}} ({{.Status}})' 2>/dev/null | head -20)
else
    CONTAINER_COUNT=0
    CONTAINER_LIST="  (docker tidak tersedia)"
fi

MSG="📊 <b>Laporan Harian VPS</b>
🖥️ Host: <code>${HOSTNAME_VAL}</code>
📅 Waktu: ${DATE_STR}

<b>Uptime</b>: ${UPTIME_STR}
<b>Load Avg</b>: ${LOAD_AVG}

<b>RAM Total</b>: ${MEM_TOTAL}
<b>RAM Tersedia</b>: ${MEM_AVAIL}
<b>Swap Terpakai</b>: ${SWAP_USED}

<b>Disk /</b>: ${DISK_INFO}

<b>Container Aktif</b>: ${CONTAINER_COUNT}
${CONTAINER_LIST}"

send_telegram "$MSG"
