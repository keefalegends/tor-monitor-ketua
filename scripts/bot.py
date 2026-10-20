#!/usr/bin/env python3
"""
bot.py - Bot Telegram interaktif untuk monitor VPS.
Menggunakan long-polling murni (requests saja, tanpa framework berat).
Hanya merespons CHAT_ID yang terdaftar di .env
"""

import os
import sys
import time
import subprocess
import requests
from pathlib import Path


ENV_PATH = Path("/opt/tor-monitor/.env")


def load_env(path: Path) -> dict:
    """Baca pasangan KEY=VALUE dari file .env, abaikan komentar."""
    if not path.exists():
        sys.exit(f"ERROR: {path} tidak ditemukan. Jalankan install.sh terlebih dahulu.")
    config = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            config[k.strip()] = v.strip()
    return config


cfg     = load_env(ENV_PATH)
TOKEN   = cfg.get("BOT_TOKEN", "")
CHAT_ID = cfg.get("CHAT_ID", "")

if not TOKEN or not CHAT_ID:
    sys.exit("ERROR: BOT_TOKEN atau CHAT_ID kosong di .env")

API_URL = f"https://api.telegram.org/bot{TOKEN}"


def send(text: str) -> None:
    """Kirim pesan HTML ke CHAT_ID."""
    try:
        requests.post(
            f"{API_URL}/sendMessage",
            data={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"},
            timeout=10,
        )
    except requests.RequestException as e:
        print(f"[send error] {e}", flush=True)


def shell(cmd: str) -> str:
    """Jalankan perintah shell, kembalikan stdout (atau stderr jika kosong)."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=15
        )
        return result.stdout.strip() or result.stderr.strip()
    except subprocess.TimeoutExpired:
        return "(timeout)"


# --- Command handlers ---

def cmd_status() -> str:
    uptime   = shell("uptime -p")
    load_avg = shell("uptime | awk -F'load average:' '{print $2}'").strip()
    mem      = shell(
        "free -m | awk '/^Mem:/{printf \"Terpakai %s MB / %s MB (%.0f%%)\","
        " $3, $2, $3/$2*100}'"
    )
    swap     = shell(
        "free -m | awk '/^Swap:/{if($2>0)"
        " printf \"Terpakai %s MB / %s MB (%.0f%%)\", $3, $2, $3/$2*100;"
        " else print \"Tidak aktif\"}'"
    )
    disk     = shell("df -h / | awk 'NR==2{printf \"%s dari %s (%s)\", $3, $2, $5}'")
    hostname = shell("hostname")

    return (
        f"🖥️ <b>Status VPS — {hostname}</b>\n\n"
        f"⏱ <b>Uptime</b>: {uptime}\n"
        f"📊 <b>Load Avg</b>:{load_avg}\n\n"
        f"🧠 <b>RAM</b>: {mem}\n"
        f"🔄 <b>Swap</b>: {swap}\n"
        f"💾 <b>Disk /</b>: {disk}"
    )


def cmd_containers() -> str:
    output = shell("docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}'")
    if not output:
        return "⚠️ Tidak ada container, atau Docker tidak tersedia."

    lines = ["🐳 <b>Status Container</b>\n"]
    for row in output.splitlines():
        parts = row.split("|")
        name   = parts[0] if len(parts) > 0 else "?"
        state  = parts[1] if len(parts) > 1 else "?"
        status = parts[2] if len(parts) > 2 else ""
        icon = "🟢" if state == "running" else "🔴"
        lines.append(f"{icon} <code>{name}</code>\n   {status}")

    return "\n".join(lines)


def cmd_help() -> str:
    return (
        "🤖 <b>Tor Monitor Bot</b>\n\n"
        "/status      — RAM, disk, swap, uptime\n"
        "/containers  — daftar semua container Docker\n"
        "/help        — pesan ini"
    )


HANDLERS = {
    "/status":     cmd_status,
    "/containers": cmd_containers,
    "/help":       cmd_help,
}


# --- Polling loop ---

def get_updates(offset: int) -> list:
    """Long-poll Telegram untuk update baru. Timeout 30 detik per request."""
    try:
        r = requests.get(
            f"{API_URL}/getUpdates",
            params={"offset": offset, "timeout": 30, "allowed_updates": ["message"]},
            timeout=35,
        )
        return r.json().get("result", [])
    except requests.RequestException:
        return []


def main() -> None:
    print(f"Bot aktif. Menunggu perintah dari chat_id={CHAT_ID}...", flush=True)
    send("✅ <b>Bot monitor aktif.</b> Ketik /help untuk daftar perintah.")
    offset = 0

    while True:
        updates = get_updates(offset)

        for update in updates:
            offset = update["update_id"] + 1
            msg     = update.get("message", {})
            from_id = str(msg.get("chat", {}).get("id", ""))
            # Ambil teks, buang @username jika ada (untuk group bot)
            text = msg.get("text", "").split("@")[0].strip()

            # Abaikan pesan dari chat ID yang tidak diotorisasi.
            if from_id != CHAT_ID:
                continue

            handler = HANDLERS.get(text)
            if handler:
                try:
                    send(handler())
                except Exception as e:
                    send(f"⚠️ Error saat menjalankan {text}: {e}")

        time.sleep(1)


if __name__ == "__main__":
    main()
