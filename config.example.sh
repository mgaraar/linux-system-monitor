# shellcheck disable=SC2034
# (variabel di bawah dipakai oleh monitor.sh setelah file ini di-source)

# Contoh konfigurasi Linux System Monitor.
#
# Salin file ini menjadi config.sh di folder yang sama dengan monitor.sh,
# lalu sesuaikan nilainya. config.sh diabaikan oleh git.
#
# Semua nilai juga bisa diberikan lewat environment variable dengan nama
# yang sama, dan argumen CLI (-s, -t, --config) selalu menang.

# Service systemd yang diperiksa.
MONITOR_SERVICE="ssh.service"

# Ambang warning persen untuk CPU, RAM, disk, dan swap.
MONITOR_THRESHOLD=80

# Folder log. Kosongkan untuk memakai folder tempat script berada.
# Path relatif dihitung dari folder script.
MONITOR_LOG_DIR=""

# Batas baris log. Saat terlampaui, hanya separuhnya yang disisakan.
# Set 0 untuk menonaktifkan rotasi.
MONITOR_LOG_MAX_LINES=5000

# Jeda antar dua sampel /proc/stat saat mengukur CPU (detik).
MONITOR_SAMPLE_INTERVAL=0.5

# Jumlah proses teratas yang ditampilkan. Set 0 untuk menonaktifkan.
MONITOR_TOP_PROCESSES=3

# File lock agar run cron tidak tumpang tindih. Kosongkan untuk menonaktifkan.
MONITOR_LOCK_FILE="/tmp/linux-system-monitor.lock"

# Webhook notifikasi (Slack, Discord, atau endpoint sendiri).
# Kosongkan untuk menonaktifkan notifikasi.
MONITOR_NOTIFY_WEBHOOK=""

# Kapan notifikasi dikirim: warning | error | always | never
MONITOR_NOTIFY_ON="warning"
