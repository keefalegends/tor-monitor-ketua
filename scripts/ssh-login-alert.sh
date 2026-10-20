#!/usr/bin/env bash
# ssh-login-alert.sh — kirim notifikasi ke Telegram saat ada login SSH.
# Letakkan di /etc/profile.d/ssh-alert.sh atau panggil dari ~/.bashrc (root)
# agar jalan saat sesi SSH terbuka.

# Hanya alert untuk sesi SSH interaktif, bukan script automation.
[[ -z "$SSH_CONNECTION" ]] && exit 0

ENV_FILE="/opt/tor-monitor/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    exit 0
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

[[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]] && exit 0

IP_REMOTE=$(echo "$SSH_CONNECTION" | awk '{print $1}')
IP_LOCAL=$(echo  "$SSH_CONNECTION" | awk '{print $3}')
PORT=$(echo      "$SSH_CONNECTION" | awk '{print $4}')
USER_LOGIN="${USER:-$(whoami)}"
HOSTNAME_VAL=$(hostname)
DATE_STR=$(date '+%Y-%m-%d %H:%M:%S WIB')

MSG="🔑 <b>Login SSH Terdeteksi</b>
🖥️ Host: <code>${HOSTNAME_VAL}</code>
👤 User: <code>${USER_LOGIN}</code>
🌐 Dari: <code>${IP_REMOTE}</code>
📍 Port: <code>${PORT}</code>
🕐 Waktu: ${DATE_STR}"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${MSG}" \
    --data-urlencode "parse_mode=HTML" \
    > /dev/null 2>&1 &
