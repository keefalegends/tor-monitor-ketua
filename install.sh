#!/usr/bin/env bash
# install.sh — setup otomatis cron + symlink + permissions.
# Jalankan sebagai root di VPS: bash install.sh

set -euo pipefail

INSTALL_DIR="/opt/tor-monitor"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && die "Jalankan sebagai root: sudo bash install.sh"

# Pastikan dependensi tersedia.
for cmd in curl docker; do
    command -v "$cmd" &>/dev/null || warn "$cmd tidak ditemukan — beberapa fitur tidak aktif"
done

info "Membuat direktori instalasi ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"

info "Menyalin skrip..."
cp -r "$REPO_DIR/scripts" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/scripts/*.sh

info "Menyiapkan file .env..."
if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
    cp "$REPO_DIR/.env.example" "${INSTALL_DIR}/.env"
    warn "File .env dibuat dari .env.example. Edit dulu sebelum lanjut:"
    warn "  nano ${INSTALL_DIR}/.env"
    read -rp "Tekan Enter setelah mengisi .env, atau Ctrl+C untuk batal..."
fi

chmod 600 "${INSTALL_DIR}/.env"

# Verifikasi .env minimal sudah diisi.
# shellcheck source=/dev/null
source "${INSTALL_DIR}/.env"
[[ "${BOT_TOKEN:-}" == "123456789:*" || -z "${BOT_TOKEN:-}" ]] && \
    die "BOT_TOKEN belum diisi di ${INSTALL_DIR}/.env"
[[ -z "${CHAT_ID:-}" || "${CHAT_ID}" == "987654321" ]] && \
    die "CHAT_ID belum diisi di ${INSTALL_DIR}/.env"

info "Mendaftarkan cron jobs..."
CRON_TMP=$(mktemp)
crontab -l 2>/dev/null | grep -v 'tor-monitor' > "$CRON_TMP" || true

cat >> "$CRON_TMP" <<EOF

# tor-monitor: cek RAM/disk/container setiap 5 menit
*/5 * * * * /bin/bash ${INSTALL_DIR}/scripts/monitor.sh >> /var/log/tor-monitor.log 2>&1

# tor-monitor: laporan harian jam 07:00
0 7 * * * /bin/bash ${INSTALL_DIR}/scripts/daily-report.sh >> /var/log/tor-monitor.log 2>&1
EOF

crontab "$CRON_TMP"
rm "$CRON_TMP"
info "Cron terdaftar."

info "Menyiapkan alert login SSH..."
SSH_ALERT_DST="/etc/profile.d/ssh-alert.sh"
cp "${INSTALL_DIR}/scripts/ssh-login-alert.sh" "$SSH_ALERT_DST"
chmod 644 "$SSH_ALERT_DST"
info "SSH alert aktif (akan jalan di sesi SSH berikutnya)."

info "Membuat file log..."
touch /var/log/tor-monitor.log
chmod 640 /var/log/tor-monitor.log

echo ""
info "Instalasi selesai!"
echo "  Monitor    : cron setiap 5 menit"
echo "  Daily report: jam 07:00 WIB setiap hari"
echo "  SSH alert  : aktif di /etc/profile.d/"
echo "  Log        : /var/log/tor-monitor.log"
echo ""
info "Uji sekarang:"
echo "  bash ${INSTALL_DIR}/scripts/monitor.sh"
echo "  bash ${INSTALL_DIR}/scripts/daily-report.sh"
