#!/usr/bin/env bash
# monitor.sh — cek RAM, disk, dan container; kirim alert ke Telegram jika ada masalah.
# Dijalankan oleh cron setiap 5 menit. Gunakan cooldown di /tmp agar tidak spam.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: file .env tidak ditemukan di $(dirname "$SCRIPT_DIR")" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

BOT_TOKEN="${BOT_TOKEN:?Set BOT_TOKEN di .env}"
CHAT_ID="${CHAT_ID:?Set CHAT_ID di .env}"
RAM_THRESHOLD="${RAM_THRESHOLD:-20}"
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"
SWAP_THRESHOLD="${SWAP_THRESHOLD:-80}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-3600}"

COOLDOWN_DIR="/tmp/tor-monitor"
mkdir -p "$COOLDOWN_DIR"

# Kirim pesan teks ke Telegram.
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "parse_mode=HTML" \
        > /dev/null
}

# Cek cooldown berdasarkan nama kunci. Return 0 jika boleh alert, 1 jika masih cooldown.
check_cooldown() {
    local key="$1"
    local flag_file="${COOLDOWN_DIR}/${key}"

    if [[ -f "$flag_file" ]]; then
        local last_sent
        last_sent=$(cat "$flag_file")
        local now
        now=$(date +%s)
        if (( now - last_sent < COOLDOWN_SECONDS )); then
            return 1  # masih cooldown, jangan kirim
        fi
    fi
    date +%s > "$flag_file"
    return 0
}

HOSTNAME_VAL=$(hostname)
ALERTS=()

# Cek RAM available (persen)
check_ram() {
    local mem_total mem_available pct_available
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    pct_available=$(( mem_available * 100 / mem_total ))

    if (( pct_available < RAM_THRESHOLD )); then
        if check_cooldown "ram_low"; then
            local mem_avail_mb=$(( mem_available / 1024 ))
            ALERTS+=("⚠️ <b>RAM Rendah</b> — tersisa ${pct_available}% (${mem_avail_mb} MB). Ambang: ${RAM_THRESHOLD}%")
        fi
    else
        rm -f "${COOLDOWN_DIR}/ram_low"
    fi
}

# Cek disk usage semua partisi yang di-mount (kecuali tmpfs/devtmpfs).
check_disk() {
    while IFS= read -r line; do
        local pct mount
        pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk '{print $6}')

        if (( pct > DISK_THRESHOLD )); then
            local key
            key="disk_full_$(echo "$mount" | tr '/' '_')"
            if check_cooldown "$key"; then
                ALERTS+=("💾 <b>Disk Hampir Penuh</b> — <code>${mount}</code> terpakai ${pct}%. Ambang: ${DISK_THRESHOLD}%")
            fi
        else
            local key
            key="disk_full_$(echo "$mount" | tr '/' '_')"
            rm -f "${COOLDOWN_DIR}/${key}"
        fi
    done < <(df -h --output=source,fstype,size,used,pcent,target 2>/dev/null \
        | awk 'NR>1 && $2!="tmpfs" && $2!="devtmpfs" && $2!="squashfs" {print}') || true
}

# Cek swap usage.
check_swap() {
    local swap_total swap_used pct_used
    swap_total=$(free | awk '/^Swap:/ {print $2}')
    swap_used=$(free  | awk '/^Swap:/ {print $3}')

    if (( swap_total == 0 )); then
        return
    fi

    pct_used=$(( swap_used * 100 / swap_total ))
    if (( pct_used > SWAP_THRESHOLD )); then
        if check_cooldown "swap_high"; then
            ALERTS+=("🔄 <b>Swap Tinggi</b> — terpakai ${pct_used}%. Ambang: ${SWAP_THRESHOLD}%")
        fi
    else
        rm -f "${COOLDOWN_DIR}/swap_high"
    fi
}

# Cek semua container: harus Running, dan jika ada healthcheck harus Healthy.
check_containers() {
    if ! command -v docker &> /dev/null; then
        return
    fi

    while IFS= read -r line; do
        local name status health
        name=$(echo   "$line" | cut -d'|' -f1)
        status=$(echo "$line" | cut -d'|' -f2)
        health=$(echo "$line" | cut -d'|' -f3)

        local key
        key="container_$(echo "$name" | tr -c '[:alnum:]' '_')"

        local is_problem=0

        if [[ "$status" != "running" ]]; then
            is_problem=1
            if check_cooldown "$key"; then
                ALERTS+=("🔴 <b>Container Mati</b> — <code>${name}</code> status: <code>${status}</code>")
            fi
        elif [[ "$health" == "unhealthy" ]]; then
            is_problem=1
            if check_cooldown "$key"; then
                ALERTS+=("🟡 <b>Container Unhealthy</b> — <code>${name}</code>")
            fi
        fi

        if (( is_problem == 0 )); then
            rm -f "${COOLDOWN_DIR}/${key}"
        fi
    done < <(docker ps -a --format '{{.Names}}|{{.State}}|{{.Health}}' 2>/dev/null)
}

check_ram
check_disk
check_swap
check_containers

if (( ${#ALERTS[@]} > 0 )); then
    MSG="🖥️ <b>Alert VPS</b> — <code>${HOSTNAME_VAL}</code>$(date '+  %Y-%m-%d %H:%M WIB')"$'\n\n'
    for alert in "${ALERTS[@]}"; do
        MSG+="${alert}"$'\n'
    done
    send_telegram "$MSG"
fi
