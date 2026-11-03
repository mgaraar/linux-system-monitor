#!/bin/bash
#
# Linux System Monitor
# Menampilkan informasi sistem (CPU, RAM, swap, disk, load) dan status satu
# service systemd, dengan opsi notifikasi webhook saat terjadi warning.
#
# Pemakaian: bash monitor.sh [opsi]   (lihat --help)
#
# Exit code: 0 = normal, 1 = warning, 2 = error

set -u

export LC_ALL=C

VERSION="2.1.0"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---------- default ----------

DEFAULT_SERVICE="ssh.service"
DEFAULT_THRESHOLD=80
DEFAULT_LOG_MAX_LINES=5000
DEFAULT_SAMPLE_INTERVAL=0.5
DEFAULT_TOP_PROCESSES=3
DEFAULT_NOTIFY_ON="warning"
DEFAULT_LOCK_FILE="/tmp/linux-system-monitor.lock"
DEFAULT_WATCH_INTERVAL=2
DEFAULT_CACHE_FILE="${TMPDIR:-/tmp}/linux-system-monitor.cpu"

# Nilai dari argumen CLI (kosong = tidak ditentukan)
CLI_SERVICE=""
CLI_THRESHOLD=""
CLI_CONFIG=""
CLI_WATCH_INTERVAL=""

JSON=false
WATCH=false
NO_LOG=false
NO_LOCK=false

usage() {
	cat <<EOF
Linux System Monitor v${VERSION}

Pemakaian: bash monitor.sh [opsi]

Opsi:
  -s, --service <nama>      Service systemd yang diperiksa (default: ${DEFAULT_SERVICE})
  -t, --threshold <1-100>   Ambang warning persen untuk CPU/RAM/DISK/swap (default: 80)
  -w, --watch [detik]       Mode watch: refresh layar terus-menerus (default: ${DEFAULT_WATCH_INTERVAL} detik)
      --no-log              Jangan tulis output ke log
      --no-lock             Jangan pakai file lock
      --config <file>       Muat konfigurasi dari file (default: config.sh di folder script)
      --json                Keluarkan hasil sebagai JSON
  -h, --help                Tampilkan bantuan ini

Konfigurasi lewat environment (contoh: MONITOR_THRESHOLD=90 bash monitor.sh):
  MONITOR_SERVICE           Nama service systemd
  MONITOR_THRESHOLD         Ambang warning persen
  MONITOR_LOG_DIR           Folder log (default: folder script)
  MONITOR_LOG_MAX_LINES     Batas baris log sebelum dipangkas (0 = nonaktif)
  MONITOR_SAMPLE_INTERVAL   Jeda sampling CPU dalam detik (default: 0.5)
  MONITOR_TOP_PROCESSES     Jumlah proses teratas yang ditampilkan (0 = nonaktif)
  MONITOR_LOCK_FILE         File lock agar tidak tumpang tindih (kosong = nonaktif)
  MONITOR_WATCH_INTERVAL    Jeda refresh mode watch dalam detik (default: ${DEFAULT_WATCH_INTERVAL})
  MONITOR_CACHE_FILE        File cache sampel CPU untuk mode watch
  MONITOR_NOTIFY_WEBHOOK    URL webhook untuk notifikasi
  MONITOR_NOTIFY_ON         Kapan notifikasi dikirim: warning|error|always|never
  MONITOR_CONFIG            Path file konfigurasi alternatif

Exit code:
  0  semua normal (atau run dilewati karena instance lain masih berjalan)
  1  ada nilai melewati threshold atau service tidak aktif
  2  data tidak tersedia / terjadi error

Contoh:
  bash monitor.sh
  bash monitor.sh -s nginx.service -t 90
  bash monitor.sh --json
  bash monitor.sh --watch 1
  MONITOR_NOTIFY_WEBHOOK="https://example.com/hook" bash monitor.sh
EOF
}

err() {
	printf 'Error: %s\n' "$1" >&2
}

warn() {
	printf 'Peringatan: %s\n' "$1" >&2
}

timestamp() {
	date '+%Y-%m-%d %H:%M:%S'
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

is_uint() {
	[[ "$1" =~ ^[0-9]+$ ]]
}

is_number() {
	[[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

# ---------- parsing argumen ----------

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-s | --service)
			[[ $# -ge 2 ]] || {
				err "opsi $1 membutuhkan nilai"
				exit 2
			}
			CLI_SERVICE="$2"
			shift 2
			;;
		--service=*)
			CLI_SERVICE="${1#*=}"
			shift
			;;
		-t | --threshold)
			[[ $# -ge 2 ]] || {
				err "opsi $1 membutuhkan nilai"
				exit 2
			}
			CLI_THRESHOLD="$2"
			shift 2
			;;
		--threshold=*)
			CLI_THRESHOLD="${1#*=}"
			shift
			;;
		--config)
			[[ $# -ge 2 ]] || {
				err "opsi $1 membutuhkan nilai"
				exit 2
			}
			CLI_CONFIG="$2"
			shift 2
			;;
		--config=*)
			CLI_CONFIG="${1#*=}"
			shift
			;;
		-w | --watch)
			WATCH=true
			# Interval opsional: hanya dikonsumsi bila berupa angka.
			if [[ $# -ge 2 ]] && is_number "$2"; then
				CLI_WATCH_INTERVAL="$2"
				shift
			fi
			shift
			;;
		--watch=*)
			WATCH=true
			CLI_WATCH_INTERVAL="${1#*=}"
			shift
			;;
		--no-log)
			NO_LOG=true
			shift
			;;
		--no-lock)
			NO_LOCK=true
			shift
			;;
		--json)
			JSON=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			err "opsi tidak dikenal: $1"
			usage >&2
			exit 2
			;;
		esac
	done
}

# ---------- konfigurasi ----------

load_config() {
	CONFIG_FILE="${CLI_CONFIG:-${MONITOR_CONFIG:-$SCRIPT_DIR/config.sh}}"

	if [[ -n "$CLI_CONFIG" && ! -f "$CONFIG_FILE" ]]; then
		err "file konfigurasi tidak ditemukan: $CONFIG_FILE"
		exit 2
	fi

	# Simpan nilai dari environment agar menang atas isi file konfigurasi.
	ENV_SERVICE="${MONITOR_SERVICE-__UNSET__}"
	ENV_THRESHOLD="${MONITOR_THRESHOLD-__UNSET__}"
	ENV_LOG_DIR="${MONITOR_LOG_DIR-__UNSET__}"
	ENV_LOG_MAX_LINES="${MONITOR_LOG_MAX_LINES-__UNSET__}"
	ENV_SAMPLE_INTERVAL="${MONITOR_SAMPLE_INTERVAL-__UNSET__}"
	ENV_TOP_PROCESSES="${MONITOR_TOP_PROCESSES-__UNSET__}"
	ENV_LOCK_FILE="${MONITOR_LOCK_FILE-__UNSET__}"
	ENV_NOTIFY_WEBHOOK="${MONITOR_NOTIFY_WEBHOOK-__UNSET__}"
	ENV_NOTIFY_ON="${MONITOR_NOTIFY_ON-__UNSET__}"
	ENV_WATCH_INTERVAL="${MONITOR_WATCH_INTERVAL-__UNSET__}"
	ENV_CACHE_FILE="${MONITOR_CACHE_FILE-__UNSET__}"

	if [[ -f "$CONFIG_FILE" ]]; then
		# shellcheck source=/dev/null
		source "$CONFIG_FILE"
	fi

	# Terapkan kembali nilai environment (prioritas di atas file konfigurasi).
	[[ "$ENV_SERVICE" == "__UNSET__" ]] || MONITOR_SERVICE="$ENV_SERVICE"
	[[ "$ENV_THRESHOLD" == "__UNSET__" ]] || MONITOR_THRESHOLD="$ENV_THRESHOLD"
	[[ "$ENV_LOG_DIR" == "__UNSET__" ]] || MONITOR_LOG_DIR="$ENV_LOG_DIR"
	[[ "$ENV_LOG_MAX_LINES" == "__UNSET__" ]] || MONITOR_LOG_MAX_LINES="$ENV_LOG_MAX_LINES"
	[[ "$ENV_SAMPLE_INTERVAL" == "__UNSET__" ]] || MONITOR_SAMPLE_INTERVAL="$ENV_SAMPLE_INTERVAL"
	[[ "$ENV_TOP_PROCESSES" == "__UNSET__" ]] || MONITOR_TOP_PROCESSES="$ENV_TOP_PROCESSES"
	[[ "$ENV_LOCK_FILE" == "__UNSET__" ]] || MONITOR_LOCK_FILE="$ENV_LOCK_FILE"
	[[ "$ENV_NOTIFY_WEBHOOK" == "__UNSET__" ]] || MONITOR_NOTIFY_WEBHOOK="$ENV_NOTIFY_WEBHOOK"
	[[ "$ENV_NOTIFY_ON" == "__UNSET__" ]] || MONITOR_NOTIFY_ON="$ENV_NOTIFY_ON"
	[[ "$ENV_WATCH_INTERVAL" == "__UNSET__" ]] || MONITOR_WATCH_INTERVAL="$ENV_WATCH_INTERVAL"
	[[ "$ENV_CACHE_FILE" == "__UNSET__" ]] || MONITOR_CACHE_FILE="$ENV_CACHE_FILE"

	SERVICE_NAME="${CLI_SERVICE:-${MONITOR_SERVICE:-$DEFAULT_SERVICE}}"
	THRESHOLD="${CLI_THRESHOLD:-${MONITOR_THRESHOLD:-$DEFAULT_THRESHOLD}}"
	LOG_DIR="${MONITOR_LOG_DIR:-$SCRIPT_DIR}"
	LOG_MAX_LINES="${MONITOR_LOG_MAX_LINES:-$DEFAULT_LOG_MAX_LINES}"
	SAMPLE_INTERVAL="${MONITOR_SAMPLE_INTERVAL:-$DEFAULT_SAMPLE_INTERVAL}"
	TOP_PROCESSES="${MONITOR_TOP_PROCESSES:-$DEFAULT_TOP_PROCESSES}"
	LOCK_FILE="${MONITOR_LOCK_FILE:-$DEFAULT_LOCK_FILE}"
	NOTIFY_WEBHOOK="${MONITOR_NOTIFY_WEBHOOK:-}"
	NOTIFY_ON="${MONITOR_NOTIFY_ON:-$DEFAULT_NOTIFY_ON}"
	WATCH_INTERVAL="${CLI_WATCH_INTERVAL:-${MONITOR_WATCH_INTERVAL:-$DEFAULT_WATCH_INTERVAL}}"
	CACHE_FILE="${MONITOR_CACHE_FILE:-$DEFAULT_CACHE_FILE}"

	# Folder log relatif dihitung dari folder script
	if [[ "$LOG_DIR" != /* ]]; then
		LOG_DIR="$SCRIPT_DIR/$LOG_DIR"
	fi
	LOG_FILE="$LOG_DIR/monitor.log"
}

validate_config() {
	if ! is_uint "$THRESHOLD" || ((THRESHOLD < 1 || THRESHOLD > 100)); then
		err "threshold harus berupa angka 1-100"
		exit 2
	fi

	if [[ -z "$SERVICE_NAME" ]]; then
		err "nama service tidak boleh kosong"
		exit 2
	fi

	if ! is_uint "$LOG_MAX_LINES"; then
		err "MONITOR_LOG_MAX_LINES harus berupa angka bulat"
		exit 2
	fi

	if ! is_uint "$TOP_PROCESSES"; then
		err "MONITOR_TOP_PROCESSES harus berupa angka bulat"
		exit 2
	fi

	if ! is_number "$SAMPLE_INTERVAL"; then
		err "MONITOR_SAMPLE_INTERVAL harus berupa angka (contoh: 0.5)"
		exit 2
	fi

	if ! is_number "$WATCH_INTERVAL"; then
		err "MONITOR_WATCH_INTERVAL harus berupa angka (contoh: 2)"
		exit 2
	fi

	if ! awk -v v="$WATCH_INTERVAL" 'BEGIN { exit !(v > 0) }'; then
		err "MONITOR_WATCH_INTERVAL harus lebih besar dari 0"
		exit 2
	fi

	if [[ -z "$CACHE_FILE" ]]; then
		err "MONITOR_CACHE_FILE tidak boleh kosong"
		exit 2
	fi

	if [[ "$WATCH" == true && "$JSON" == true ]]; then
		err "opsi --watch tidak dapat digabung dengan --json"
		exit 2
	fi

	case "$NOTIFY_ON" in
	warning | error | always | never) ;;
	*)
		err "MONITOR_NOTIFY_ON harus salah satu dari: warning, error, always, never"
		exit 2
		;;
	esac

	if [[ -n "$NOTIFY_WEBHOOK" ]] && ! command -v curl >/dev/null 2>&1; then
		warn "curl tidak tersedia, notifikasi webhook dinonaktifkan"
		NOTIFY_WEBHOOK=""
	fi
}

# ---------- lock & rotasi log ----------

acquire_lock() {
	[[ -n "$LOCK_FILE" ]] || return 0

	if ! command -v flock >/dev/null 2>&1; then
		warn "flock tidak tersedia, lock dilewati"
		return 0
	fi

	# fd 9 dipertahankan sampai script selesai
	if ! exec 9>"$LOCK_FILE"; then
		warn "tidak dapat membuat file lock $LOCK_FILE, lock dilewati"
		return 0
	fi

	if ! flock -n 9; then
		warn "instance lain sedang berjalan ($LOCK_FILE), run ini dilewati"
		return 1
	fi
}

rotate_log() {
	is_uint "$LOG_MAX_LINES" || return 0
	((LOG_MAX_LINES > 0)) || return 0
	[[ -f "$LOG_FILE" ]] || return 0

	local lines keep
	lines="$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)"
	lines="${lines//[[:space:]]/}"
	is_uint "$lines" || return 0
	((lines > LOG_MAX_LINES)) || return 0

	keep=$((LOG_MAX_LINES / 2))
	((keep < 1)) && keep=1

	if tail -n "$keep" "$LOG_FILE" >"$LOG_FILE.tmp" 2>/dev/null; then
		mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null || rm -f "$LOG_FILE.tmp"
	else
		rm -f "$LOG_FILE.tmp"
	fi
}

# ---------- pengambilan metrik ----------

# Baca akumulasi waktu CPU dari /proc/stat lalu cetak 8 nilai pertama.
read_cpu_times() {
	local _ user nice system idle iowait irq softirq steal rest
	read -r _ user nice system idle iowait irq softirq steal rest </proc/stat || return 1
	printf '%s %s %s %s %s %s %s %s\n' \
		"${user:-0}" "${nice:-0}" "${system:-0}" "${idle:-0}" \
		"${iowait:-0}" "${irq:-0}" "${softirq:-0}" "${steal:-0}"
}

# Hitung persentase CPU dari dua sampel /proc/stat.
# Dipisah dari pembacaan agar bisa diuji tanpa menunggu sampling.
cpu_percent_from_samples() {
	local before="$1"
	local after="$2"

	awk -v a="$before" -v b="$after" 'BEGIN {
		n = split(a, x, " ")
		split(b, y, " ")
		if (n < 4) exit 1

		total_a = 0
		total_b = 0
		for (i = 1; i <= n; i++) {
			total_a += x[i]
			total_b += y[i]
		}

		# kolom 4 = idle, kolom 5 = iowait
		idle_a = x[4]
		idle_b = y[4]
		if (n >= 5) {
			idle_a += x[5]
			idle_b += y[5]
		}

		delta_total = total_b - total_a
		delta_idle = idle_b - idle_a
		if (delta_total <= 0) exit 1

		printf "%.0f", (delta_total - delta_idle) * 100 / delta_total
	}'
}

get_cpu_usage() {
	local before after

	before="$(read_cpu_times)" || return 1
	sleep "$SAMPLE_INTERVAL" 2>/dev/null || sleep 1
	after="$(read_cpu_times)" || return 1

	cpu_percent_from_samples "$before" "$after"
}

# ---------- cache sampel CPU untuk mode watch ----------

read_cpu_cache() {
	[[ -f "$CACHE_FILE" ]] || return 1

	local sample
	sample="$(<"$CACHE_FILE")"
	sample="${sample//[[:space:]]/ }"
	sample="${sample# }"
	sample="${sample% }"
	[[ -n "$sample" ]] || return 1

	printf '%s\n' "$sample"
}

write_cpu_cache() {
	printf '%s\n' "$1" >"$CACHE_FILE" 2>/dev/null
}

# Simpan sampel sekarang sebagai pembanding untuk frame berikutnya.
prime_cpu_cache() {
	local sample
	sample="$(read_cpu_times)" || return 1
	write_cpu_cache "$sample"
}

# Hitung CPU memakai sampel terakhir di cache, lalu perbarui cache.
# Frame pertama tanpa cache dianggap belum punya pembanding (exit 1).
get_cpu_usage_cached() {
	local before after percent

	after="$(read_cpu_times)" || return 1
	before="$(read_cpu_cache)" || return 1

	percent="$(cpu_percent_from_samples "$before" "$after")" || {
		write_cpu_cache "$after" || true
		return 1
	}

	write_cpu_cache "$after" || true
	printf '%s' "$percent"
}

# Pemakaian RAM berdasarkan kolom available.
get_ram_usage() {
	free -b 2>/dev/null | awk '/^Mem:/ {
		if (NF >= 7 && $2 > 0)
			printf "%.0f", (($2 - $7) / $2) * 100
		exit
	}'
}

# Pemakaian swap. Mencetak "none" bila swap tidak dikonfigurasi.
get_swap_usage() {
	free -b 2>/dev/null | awk '/^Swap:/ {
		if ($2 > 0)
			printf "%.0f", (($2 - $4) / $2) * 100
		else
			printf "none"
		exit
	}'
}

# Pemakaian disk root.
get_disk_usage() {
	df -P / 2>/dev/null | awk 'NR == 2 {
		gsub(/%/, "", $5)
		print $5
	}'
}

# Load average 1/5/15 menit, dipisah spasi.
get_load() {
	local l1 l5 l15 rest
	read -r l1 l5 l15 rest </proc/loadavg || return 1
	[[ -n "$l1" && -n "$l5" && -n "$l15" ]] || return 1
	printf '%s %s %s\n' "$l1" "$l5" "$l15"
}

load_is_warning() {
	awk -v l="$1" -v c="$2" 'BEGIN { exit !(l >= c) }'
}

get_cpu_count() {
	local count
	count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
	is_uint "$count" && ((count > 0)) || count=1
	printf '%s' "$count"
}

# normal | warning | error
classify() {
	local value="$1"
	local limit="$2"

	if [[ ! "$value" =~ ^[0-9]+$ ]]; then
		echo "error"
	elif ((value >= limit)); then
		echo "warning"
	else
		echo "normal"
	fi
}

# ---------- pemeriksaan service ----------

SERVICE_NAME_USED=""
SERVICE_STATE=""
SERVICE_DETAIL=""

check_service() {
	local service="$1"
	local load_state=""
	local active_state=""

	SERVICE_NAME_USED="$service"

	if ! command -v systemctl >/dev/null 2>&1; then
		SERVICE_STATE="unavailable"
		SERVICE_DETAIL="systemctl tidak tersedia"
		return
	fi

	if [[ "$(ps -p 1 -o comm= 2>/dev/null || true)" != "systemd" ]]; then
		SERVICE_STATE="unavailable"
		SERVICE_DETAIL="systemd tidak berjalan sebagai PID 1"
		return
	fi

	load_state="$(systemctl show "$service" --property=LoadState --value 2>/dev/null || true)"
	active_state="$(systemctl show "$service" --property=ActiveState --value 2>/dev/null || true)"

	# systemd lama belum mendukung --value
	if [[ -z "$load_state" || -z "$active_state" ]]; then
		load_state="$(systemctl show "$service" --property=LoadState 2>/dev/null | cut -d= -f2 || true)"
		active_state="$(systemctl show "$service" --property=ActiveState 2>/dev/null | cut -d= -f2 || true)"
	fi

	if [[ "$load_state" == "not-found" ]]; then
		SERVICE_STATE="not-found"
		SERVICE_DETAIL="service tidak ditemukan"
		return
	fi

	if [[ -z "$load_state" ]]; then
		SERVICE_STATE="unavailable"
		SERVICE_DETAIL="status service tidak dapat dibaca"
		return
	fi

	if [[ "$active_state" == "active" ]]; then
		SERVICE_STATE="active"
		SERVICE_DETAIL="active"
	else
		SERVICE_STATE="inactive"
		SERVICE_DETAIL="${active_state:-unknown}"
	fi
}

# ---------- format output ----------

status_label() {
	case "$1" in
	normal) echo "NORMAL" ;;
	warning) echo "WARNING" ;;
	error) echo "ERROR" ;;
	*) echo "-" ;;
	esac
}

overall_label() {
	case "$1" in
	ok) echo "NORMAL" ;;
	warning) echo "WARNING" ;;
	*) echo "ERROR" ;;
	esac
}

percent_text() {
	if is_uint "$1"; then
		printf '%s%%' "$1"
	else
		printf 'data tidak tersedia'
	fi
}

json_percent() {
	local name="$1"
	local value="$2"
	local status="$3"

	if is_uint "$value"; then
		printf '"%s":{"value":%s,"status":"%s"}' "$name" "$value" "$status"
	else
		printf '"%s":{"value":null,"status":"%s"}' "$name" "$status"
	fi
}

service_line() {
	case "$SERVICE_STATE" in
	active) printf '%s: ACTIVE\n' "$SERVICE_NAME_USED" ;;
	inactive) printf '%s: NOT ACTIVE (%s)\n' "$SERVICE_NAME_USED" "$SERVICE_DETAIL" ;;
	not-found) printf '%s: NOT FOUND\n' "$SERVICE_NAME_USED" ;;
	*) printf '%s: TIDAK TERSEDIA (%s)\n' "$SERVICE_NAME_USED" "$SERVICE_DETAIL" ;;
	esac
}

# ---------- notifikasi ----------

notify() {
	local status="$1"
	local summary="$2"
	local message payload

	[[ -n "$NOTIFY_WEBHOOK" ]] || return 0
	[[ "$WATCH" != true ]] || return 0

	case "$NOTIFY_ON" in
	never) return 0 ;;
	error) [[ "$status" == "error" ]] || return 0 ;;
	warning) [[ "$status" == "warning" || "$status" == "error" ]] || return 0 ;;
	always) ;;
	esac

	message="$(printf '[%s] %s - %s' "$(overall_label "$status")" "$(hostname)" "$summary")"
	payload="$(printf '{"text":"%s","content":"%s","hostname":"%s","status":"%s"}' \
		"$(json_escape "$message")" \
		"$(json_escape "$message")" \
		"$(json_escape "$(hostname)")" \
		"$status")"

	curl -fsS -m 5 -H 'Content-Type: application/json' -d "$payload" "$NOTIFY_WEBHOOK" >/dev/null 2>&1 || true
}

# ---------- program utama ----------

main() {
	local cpu_usage ram_usage swap_usage disk_usage
	local cpu_status ram_status swap_status disk_status
	local load_all load1 load5 load15 load_status cpu_count
	local overall code status summary procs

	if [[ "$WATCH" == true ]]; then
		cpu_usage="$(get_cpu_usage_cached || get_cpu_usage || true)"
	else
		cpu_usage="$(get_cpu_usage || true)"
	fi
	ram_usage="$(get_ram_usage || true)"
	swap_usage="$(get_swap_usage || true)"
	disk_usage="$(get_disk_usage || true)"
	load_all="$(get_load || true)"
	cpu_count="$(get_cpu_count)"

	cpu_status="$(classify "$cpu_usage" "$THRESHOLD")"
	ram_status="$(classify "$ram_usage" "$THRESHOLD")"
	disk_status="$(classify "$disk_usage" "$THRESHOLD")"

	if [[ "$swap_usage" == "none" ]]; then
		swap_status="skipped"
	elif is_uint "$swap_usage"; then
		swap_status="$(classify "$swap_usage" "$THRESHOLD")"
	else
		swap_status="error"
	fi

	if [[ -n "$load_all" ]]; then
		read -r load1 load5 load15 <<<"$load_all"
		if load_is_warning "$load1" "$cpu_count"; then
			load_status="warning"
		else
			load_status="normal"
		fi
	else
		load1="-"
		load5="-"
		load15="-"
		load_status="error"
	fi

	check_service "$SERVICE_NAME"
	# Distribusi RHEL memakai sshd.service, bukan ssh.service.
	if [[ "$SERVICE_NAME" == "ssh.service" && "$SERVICE_STATE" == "not-found" ]]; then
		check_service "sshd.service"
	fi

	overall="ok"
	for status in "$cpu_status" "$ram_status" "$disk_status" "$swap_status" "$load_status"; do
		case "$status" in
		error)
			overall="error"
			;;
		warning)
			[[ "$overall" == "error" ]] || overall="warning"
			;;
		esac
	done

	case "$SERVICE_STATE" in
	active) ;;
	inactive)
		[[ "$overall" == "error" ]] || overall="warning"
		;;
	*) overall="error" ;;
	esac

	case "$overall" in
	ok) code=0 ;;
	warning) code=1 ;;
	*) code=2 ;;
	esac

	summary="CPU $(percent_text "$cpu_usage"), RAM $(percent_text "$ram_usage"), DISK $(percent_text "$disk_usage")"

	if [[ "$JSON" == true ]]; then
		printf '{"timestamp":"%s","hostname":"%s","version":"%s","threshold":%s,' \
			"$(timestamp)" "$(json_escape "$(hostname)")" "$VERSION" "$THRESHOLD"
		printf '"metrics":{%s,%s,%s,%s,' \
			"$(json_percent "cpu" "$cpu_usage" "$cpu_status")" \
			"$(json_percent "ram" "$ram_usage" "$ram_status")" \
			"$(json_percent "disk" "$disk_usage" "$disk_status")" \
			"$(json_percent "swap" "$swap_usage" "$swap_status")"
		if is_number "$load1"; then
			printf '"load":{"value":%s,"cores":%s,"status":"%s"}},' "$load1" "$cpu_count" "$load_status"
		else
			printf '"load":{"value":null,"cores":%s,"status":"%s"}},' "$cpu_count" "$load_status"
		fi
		printf '"service":{"name":"%s","state":"%s","detail":"%s"},' \
			"$(json_escape "$SERVICE_NAME_USED")" "$SERVICE_STATE" "$(json_escape "$SERVICE_DETAIL")"
		printf '"status":"%s","exit_code":%s}\n' "$overall" "$code"

		notify "$overall" "$summary"
		return "$code"
	fi

	echo ""
	echo "================================"
	echo "    INFORMASI SISTEM"
	echo "================================"
	echo "Waktu    : $(timestamp)"
	echo "Hostname : $(hostname)"
	echo "Versi    : $VERSION"

	echo ""
	echo "--- STATUS  ---"
	printf 'CPU   : %s - %s\n' "$(status_label "$cpu_status")" "$(percent_text "$cpu_usage")"
	printf 'RAM   : %s - %s\n' "$(status_label "$ram_status")" "$(percent_text "$ram_usage")"
	if [[ "$swap_status" == "skipped" ]]; then
		printf 'SWAP  : - (tidak dikonfigurasi)\n'
	else
		printf 'SWAP  : %s - %s\n' "$(status_label "$swap_status")" "$(percent_text "$swap_usage")"
	fi
	printf 'DISK  : %s - %s\n' "$(status_label "$disk_status")" "$(percent_text "$disk_usage")"
	printf 'LOAD  : %s - %s / %s / %s (%s core)\n' \
		"$(status_label "$load_status")" "$load1" "$load5" "$load15" "$cpu_count"

	echo ""
	echo "--- DETAIL MEMORI ---"
	free -h

	echo ""
	echo "--- DETAIL DISK ---"
	df -h /

	if is_uint "$TOP_PROCESSES" && ((TOP_PROCESSES > 0)); then
		procs="$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n $((TOP_PROCESSES + 1)) || true)"
		echo ""
		echo "--- PROSES TERATAS (CPU) ---"
		if [[ -n "$procs" ]]; then
			printf '%s\n' "$procs"
		else
			echo "tidak dapat membaca daftar proses"
		fi
	fi

	echo ""
	echo "--- PEMERIKSAAN SERVICE ---"
	service_line

	echo ""
	echo "================================"
	echo "Status keseluruhan: $(overall_label "$overall")"
	echo "================================"

	notify "$overall" "$summary"

	return "$code"
}

# ---------- mode watch ----------

WATCH_SCREEN=false

watch_cleanup() {
	[[ "$WATCH_SCREEN" == true ]] || return 0
	WATCH_SCREEN=false
	tput cnorm 2>/dev/null || true
	tput rmcup 2>/dev/null || true
}

watch_enter_screen() {
	if ! command -v tput >/dev/null 2>&1 || [[ -z "${TERM:-}" ]]; then
		warn "tput/TERM tidak tersedia, mode watch berjalan tanpa layar alternatif"
		return 0
	fi

	if tput smcup 2>/dev/null; then
		WATCH_SCREEN=true
		tput civis 2>/dev/null || true
	fi
}

watch_clear() {
	if [[ "$WATCH_SCREEN" == true ]] && tput clear 2>/dev/null; then
		return 0
	fi
	printf '\033[2J\033[H'
}

run_watch() {
	local iterations="${MONITOR_WATCH_ITERATIONS:-0}"
	local frames=0

	if ! is_uint "$iterations"; then
		err "MONITOR_WATCH_ITERATIONS harus berupa angka bulat"
		return 2
	fi

	trap watch_cleanup EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	trap 'exit 129' HUP

	watch_enter_screen

	# Mulai dari sampel baru agar frame pertama hanya mencakup satu interval.
	prime_cpu_cache || true

	while true; do
		sleep "$WATCH_INTERVAL" 2>/dev/null || sleep 1
		watch_clear
		main || true

		frames=$((frames + 1))
		if ((iterations > 0 && frames >= iterations)); then
			break
		fi
	done

	watch_cleanup
	trap - EXIT INT TERM HUP
	return 0
}

# ---------- bootstrap ----------

run_cli() {
	parse_args "$@"
	load_config
	validate_config

	if [[ "$WATCH" == true ]]; then
		run_watch
		return $?
	fi

	if [[ "$NO_LOCK" != true ]] && ! acquire_lock; then
		return 0
	fi

	if [[ "$NO_LOG" == true ]]; then
		main
		return $?
	fi

	local log_writable=false
	if mkdir -p "$LOG_DIR" 2>/dev/null && [[ -w "$LOG_DIR" ]]; then
		log_writable=true
	fi

	if [[ "$log_writable" == true ]]; then
		rotate_log
		main | tee -a "$LOG_FILE"
		return "${PIPESTATUS[0]}"
	fi

	warn "direktori $LOG_DIR tidak dapat ditulisi, output tidak dicatat ke log"
	main
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	run_cli "$@"
	exit $?
fi
