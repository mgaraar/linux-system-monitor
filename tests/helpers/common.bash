# Helper bersama untuk seluruh test bats.
# Fake binary sengaja ditulis dalam single quotes agar tidak diekspansi di sini.
# shellcheck disable=SC2016,SC2119,SC2120

repo_root() {
	printf '%s' "$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

common_setup() {
	REPO_ROOT="$(repo_root)"
	export MONITOR="$REPO_ROOT/monitor.sh"
	export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$FAKE_BIN"
	export PATH="$FAKE_BIN:$PATH"

	# Isolasi: jangan pernah menyentuh log, lock, atau webhook sungguhan.
	export MONITOR_LOCK_FILE=""
	export MONITOR_LOG_DIR="$BATS_TEST_TMPDIR/logs"
	export MONITOR_LOG_MAX_LINES=0
	export MONITOR_TOP_PROCESSES=0
	export MONITOR_SAMPLE_INTERVAL=0.05
	export MONITOR_NOTIFY_WEBHOOK=""
	export MONITOR_NOTIFY_ON="never"
	export MONITOR_CACHE_FILE="$BATS_TEST_TMPDIR/cpu.cache"
}

write_fake() {
	local name="$1"
	local body="$2"

	printf '#!/bin/bash\n%s\n' "$body" >"$FAKE_BIN/$name"
	chmod +x "$FAKE_BIN/$name"
}

# `ps` palsu: PID 1 dianggap systemd dan daftar proses statis.
fake_ps_systemd() {
	write_fake ps 'if [[ "$1" == "-p" ]]; then
	echo systemd
	exit 0
fi
printf "    PID COMMAND         %%CPU %%MEM\n      1 systemd          0.1  0.1\n"'
}

# `ps` palsu yang menandakan PID 1 bukan systemd (mis. container).
fake_ps_nonsystemd() {
	write_fake ps 'if [[ "$1" == "-p" ]]; then
	echo init
	exit 0
fi
printf "    PID COMMAND         %%CPU %%MEM\n      1 init             0.1  0.1\n"'
}

# `df` palsu dengan pemakaian root yang bisa diatur.
fake_df_root() {
	local percent="${1:-20}"

	write_fake df "printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/sda1 1000000 100000 900000 ${percent}%% /\\n'"
}

# `free` palsu: RAM ~1% terpakai, swap bisa diatur.
fake_free() {
	local swap_total="${1:-2000000000}"

	write_fake free "if [[ \"\$1\" == \"-b\" ]]; then
	printf 'Mem: 8000000000 1000000000 6000000000 10000000 900000000 7900000000\nSwap: ${swap_total} 0 ${swap_total}\n'
else
	printf 'Mem: 8.0Gi\\n'
fi"
}

# `free` palsu tanpa kolom available (procps lama).
fake_free_legacy() {
	write_fake free 'printf "Mem: 8000000000 1000000000 6000000000 10000000 900000000\n"'
}

# `systemctl` palsu dengan pemetaan service sederhana.
fake_systemctl_default() {
	write_fake systemctl 'service="$2"
load="loaded"
active="active"
case "$service" in
missing.service) load="not-found"; active="inactive" ;;
inactive.service) load="loaded"; active="failed" ;;
esac
if [[ " $* " == *" --value "* ]]; then
	case "$*" in
	*LoadState*) echo "$load" ;;
	*ActiveState*) echo "$active" ;;
	esac
else
	case "$*" in
	*LoadState*) echo "LoadState=$load" ;;
	*ActiveState*) echo "ActiveState=$active" ;;
	esac
fi'
}

install_default_fakes() {
	fake_free
	fake_df_root
	fake_ps_systemd
	fake_systemctl_default
}
