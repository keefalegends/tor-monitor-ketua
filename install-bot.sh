#!/usr/bin/env bash
# install-bot.sh — pasang bot Telegram interaktif sebagai systemd service.
# Jalankan sebagai root: bash install-bot.sh

set -euo pipefail

INSTALL_DIR="/opt/tor-monitor"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="tor-monitor-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && die "Jalankan sebagai root: sudo bash install-bot.sh"

[[ ! -f "${INSTALL_DIR}/.env" ]] && \
    die ".env tidak ditemukan di ${INSTALL_DIR}. Jalankan install.sh terlebih dahulu."

info "Mengecek Python 3..."
command -v python3 &>/dev/null || die "python3 tidak terinstal. Jalankan: apt install python3"

info "Menginstal library requests..."
# Coba via apt dulu (aman di Ubuntu 22.04+ yang menerapkan PEP 668).
# Fallback ke pip --break-system-packages jika paket apt tidak tersedia.
if apt-get install -y -qq python3-requests 2>/dev/null; then
    info "requests terinstal via apt."
elif python3 -m pip install --quiet --break-system-packages requests 2>/dev/null; then
    info "requests terinstal via pip."
else
    die "Gagal instal requests. Coba manual: apt install python3-requests"
fi

info "Menyalin bot.py..."
cp "${REPO_DIR}/scripts/bot.py" "${INSTALL_DIR}/scripts/bot.py"
chmod 750 "${INSTALL_DIR}/scripts/bot.py"

info "Mendaftarkan systemd service..."
cp "${REPO_DIR}/systemd/${SERVICE_NAME}.service" "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

echo ""
info "Bot berhasil dipasang dan berjalan!"
echo ""
echo "  Cek status : systemctl status ${SERVICE_NAME}"
echo "  Lihat log  : journalctl -u ${SERVICE_NAME} -f"
echo "  Stop bot   : systemctl stop ${SERVICE_NAME}"
echo "  Restart    : systemctl restart ${SERVICE_NAME}"
echo ""
warn "Coba ketik /help di Telegram — bot harus langsung balas."
