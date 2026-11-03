#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
	install_default_fakes
}

@test "run normal menghasilkan exit 0 dan status NORMAL" {
	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Status keseluruhan: NORMAL"* ]]
	[[ "$output" == *"RAM   : NORMAL - 1%"* ]]
	[[ "$output" == *"DISK  : NORMAL - 20%"* ]]
	[[ "$output" == *"ssh.service: ACTIVE"* ]]
}

@test "output JSON valid dan berisi semua metrik" {
	run bash "$MONITOR" --json
	[ "$status" -eq 0 ]

	echo "$output" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["metrics"]["ram"]["value"] == 1, data
assert data["metrics"]["disk"]["value"] == 20, data
assert data["metrics"]["swap"]["status"] == "normal", data
assert data["metrics"]["cpu"]["value"] is None or 0 <= data["metrics"]["cpu"]["value"] <= 100
assert data["service"]["state"] == "active", data
assert data["status"] == "ok", data
assert data["exit_code"] == 0, data
'
}

@test "threshold dari environment memicu warning" {
	export MONITOR_THRESHOLD=10
	run bash "$MONITOR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"DISK  : WARNING - 20%"* ]]
	[[ "$output" == *"Status keseluruhan: WARNING"* ]]
}

@test "disk di atas threshold memicu warning" {
	fake_df_root 90
	run bash "$MONITOR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"DISK  : WARNING - 90%"* ]]
}

@test "swap tidak dikonfigurasi menjadi skipped" {
	fake_free 0
	run bash "$MONITOR" --json
	[ "$status" -eq 0 ]

	echo "$output" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["metrics"]["swap"]["value"] is None, data
assert data["metrics"]["swap"]["status"] == "skipped", data
'
}

@test "free tanpa kolom available menghasilkan error" {
	fake_free_legacy
	run bash "$MONITOR"
	[ "$status" -eq 2 ]
	[[ "$output" == *"RAM   : ERROR"* ]]
}

@test "service tidak aktif memicu warning" {
	write_fake systemctl 'service="$2"
load="loaded"
active="failed"
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

	run bash "$MONITOR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ssh.service: NOT ACTIVE (failed)"* ]]
}

@test "ssh.service tidak ada, fallback ke sshd.service" {
	write_fake systemctl 'service="$2"
case "$service" in
ssh.service) load="not-found"; active="inactive" ;;
sshd.service) load="loaded"; active="active" ;;
*) load="not-found"; active="inactive" ;;
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

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[[ "$output" == *"sshd.service: ACTIVE"* ]]
}

@test "systemd bukan PID 1 membuat run berakhir error" {
	fake_ps_nonsystemd
	run bash "$MONITOR"
	[ "$status" -eq 2 ]
	[[ "$output" == *"TIDAK TERSEDIA"* ]]
}

@test "service yang benar-benar tidak ada membuat run error" {
	write_fake systemctl 'if [[ " $* " == *" --value "* ]]; then
	case "$*" in
	*LoadState*) echo "not-found" ;;
	*ActiveState*) echo "inactive" ;;
	esac
else
	case "$*" in
	*LoadState*) echo "LoadState=not-found" ;;
	*ActiveState*) echo "ActiveState=inactive" ;;
	esac
fi'

	run bash "$MONITOR"
	[ "$status" -eq 2 ]
	[[ "$output" == *"NOT FOUND"* ]]
}

@test "--watch menampilkan satu frame dan tidak menulis log" {
	export MONITOR_WATCH_ITERATIONS=1

	run bash "$MONITOR" --watch 0.1
	[ "$status" -eq 0 ]
	[[ "$output" == *"INFORMASI SISTEM"* ]]
	[[ "$output" == *"Status keseluruhan: NORMAL"* ]]
	[ ! -f "$MONITOR_LOG_DIR/monitor.log" ]
}
