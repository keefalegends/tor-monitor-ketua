# tor-monitor-ketua

Monitor ringan untuk VPS Ubuntu menggunakan Bash + Telegram Bot API.  `curl` dan `cron`.

## Fitur

| Fitur | Detail |
|---|---|
| Alert RAM rendah | Notifikasi jika RAM available < 20% (configurable) |
| Alert disk penuh | Notifikasi jika disk usage > 85% (configurable) |
| Alert swap tinggi | Notifikasi jika swap usage > 80% (configurable) |
| Alert container mati/unhealthy | Cek semua container Docker setiap 5 menit |
| Alert login SSH | Kirim IP + waktu saat ada sesi SSH baru |
| Laporan harian | Ringkasan uptime, RAM, disk, dan daftar container jam 07.00 |
| Cooldown anti-spam | Setiap alert punya cooldown 1 jam (configurable) |

## Struktur Repo

```
tor-monitor-ketua/
├── scripts/
│   ├── monitor.sh          # Cek RAM, disk, swap, container
│   ├── daily-report.sh     # Laporan harian ke Telegram
│   └── ssh-login-alert.sh  # Alert login SSH
├── systemd/                # (untuk pengembangan selanjutnya)
├── docs/                   # Diagram dan screenshot
├── .env.example            # Template konfigurasi
├── install.sh              # Setup otomatis
└── README.md
```

## Prasyarat

- Ubuntu VPS (akses root)
- `curl` terinstal
- Docker (opsional, untuk monitor container)
- Telegram Bot Token — buat lewat [@BotFather](https://t.me/BotFather)
- Chat ID — cek lewat [@userinfobot](https://t.me/userinfobot)

## Instalasi

### 1. Clone repo

```bash
git clone https://github.com/keefalegends/tor-monitor-ketua.git /opt/tor-monitor-src
cd /opt/tor-monitor-src
```

### 2. Jalankan installer

```bash
sudo bash install.sh
```

Installer akan:
- Menyalin skrip ke `/opt/tor-monitor/`
- Membuat `.env` dari `.env.example` (isi BOT_TOKEN dan CHAT_ID)
- Mendaftarkan cron untuk monitor (setiap 5 menit) dan laporan harian (07.00)
- Mengaktifkan alert login SSH via `/etc/profile.d/`

### 3. Isi konfigurasi

```bash
nano /opt/tor-monitor/.env
```

```env
BOT_TOKEN=123456789:AABBccddeeff...   # dari BotFather
CHAT_ID=987654321                      # dari userinfobot
RAM_THRESHOLD=20                       # alert jika RAM < 20%
DISK_THRESHOLD=85                      # alert jika disk > 85%
SWAP_THRESHOLD=80                      # alert jika swap > 80%
COOLDOWN_SECONDS=3600                  # cooldown per alert (1 jam)
```

## Cara Menguji

### Uji monitor manual

```bash
bash /opt/tor-monitor/scripts/monitor.sh
```

### Picu alert RAM palsu

Turunkan threshold sementara, lalu jalankan:

```bash
# Set RAM_THRESHOLD=99 sementara agar pasti alert
RAM_THRESHOLD=99 bash /opt/tor-monitor/scripts/monitor.sh
```

### Picu alert disk palsu

```bash
DISK_THRESHOLD=1 bash /opt/tor-monitor/scripts/monitor.sh
```

### Picu alert container

Matikan satu container sementara:

```bash
docker stop hariyuka_frontend
bash /opt/tor-monitor/scripts/monitor.sh
docker start hariyuka_frontend
```

### Uji laporan harian

```bash
bash /opt/tor-monitor/scripts/daily-report.sh
```

### Uji alert SSH

Buka sesi SSH baru ke VPS — notifikasi langsung masuk ke Telegram.

### Cek log

```bash
tail -f /var/log/tor-monitor.log
```

### Reset cooldown (agar alert bisa terkirim lagi saat test)

```bash
rm -f /tmp/tor-monitor/*
```

## Cara Kerja

```
Cron (*/5 menit)
    └── monitor.sh
            ├── Baca /proc/meminfo  → cek RAM %
            ├── df -h               → cek disk %
            ├── free                → cek swap %
            └── docker ps -a        → cek status + health container
                    │
                    └── Jika ada masalah + cooldown belum aktif
                            └── curl Telegram Bot API → alert
```

Cooldown disimpan di `/tmp/tor-monitor/<key>` berisi timestamp terakhir alert. Saat kondisi normal kembali, file cooldown dihapus otomatis agar alert bisa muncul lagi saat masalah berikutnya.

## Lisensi

MIT
