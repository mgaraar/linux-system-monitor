#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
	install_default_fakes
	export LOG_FILE="$BATS_TEST_TMPDIR/logs/monitor.log"
}

@test "log dipangkas saat melebihi batas baris" {
	export MONITOR_LOG_MAX_LINES=10
	mkdir -p "$BATS_TEST_TMPDIR/logs"
	seq 1 30 >"$LOG_FILE"

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[ "$(head -n 1 "$LOG_FILE")" = "26" ]
}

@test "rotasi nonaktif saat batas 0" {
	export MONITOR_LOG_MAX_LINES=0
	mkdir -p "$BATS_TEST_TMPDIR/logs"
	seq 1 30 >"$LOG_FILE"

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[ "$(head -n 1 "$LOG_FILE")" = "1" ]
}

@test "direktori log tidak writable tetap menjalankan monitor" {
	[ "$EUID" -eq 0 ] && skip "root mengabaikan permission direktori"

	local readonly_dir="$BATS_TEST_TMPDIR/readonly"
	mkdir -p "$readonly_dir"
	chmod 500 "$readonly_dir"

	export MONITOR_LOG_DIR="$readonly_dir/sub"

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[[ "$output" == *"tidak dapat ditulisi"* ]]

	chmod 700 "$readonly_dir"
}

@test "setiap run menambahkan output ke log" {
	mkdir -p "$BATS_TEST_TMPDIR/logs"

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[[ "$(cat "$LOG_FILE")" == *"INFORMASI SISTEM"* ]]

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[ "$(grep -c 'INFORMASI SISTEM' "$LOG_FILE")" -eq 2 ]
}
