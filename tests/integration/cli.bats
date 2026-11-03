#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
}

@test "--help menampilkan bantuan dan exit 0" {
	run bash "$MONITOR" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Pemakaian:"* ]]
	[[ "$output" == *"--json"* ]]
}

@test "opsi tidak dikenal ditolak dengan exit 2" {
	run bash "$MONITOR" --tidak-ada
	[ "$status" -eq 2 ]
	[[ "$output" == *"tidak dikenal"* ]]
}

@test "threshold 0 ditolak" {
	run bash "$MONITOR" -t 0
	[ "$status" -eq 2 ]
	[[ "$output" == *"threshold"* ]]
}

@test "threshold di atas 100 ditolak" {
	run bash "$MONITOR" --threshold=101
	[ "$status" -eq 2 ]
}

@test "threshold bukan angka ditolak" {
	run bash "$MONITOR" --threshold=abc
	[ "$status" -eq 2 ]
}

@test "opsi yang butuh nilai tanpa nilai ditolak" {
	run bash "$MONITOR" -s
	[ "$status" -eq 2 ]
	[[ "$output" == *"membutuhkan nilai"* ]]
}

@test "file konfigurasi yang tidak ada ditolak" {
	run bash "$MONITOR" --config "$BATS_TEST_TMPDIR/tidak-ada.sh"
	[ "$status" -eq 2 ]
	[[ "$output" == *"tidak ditemukan"* ]]
}

@test "konfigurasi environment yang invalid ditolak" {
	export MONITOR_NOTIFY_ON="kadang"
	run bash "$MONITOR"
	[ "$status" -eq 2 ]
	[[ "$output" == *"MONITOR_NOTIFY_ON"* ]]
}

@test "--help menyebut mode watch dan opsi terkait" {
	run bash "$MONITOR" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"--watch"* ]]
	[[ "$output" == *"--no-log"* ]]
	[[ "$output" == *"--no-lock"* ]]
	[[ "$output" == *"MONITOR_WATCH_INTERVAL"* ]]
}

@test "--watch tanpa nilai memakai interval default" {
	run bash -c 'source "$1"; parse_args --watch; printf "%s|%s" "$WATCH" "$CLI_WATCH_INTERVAL"' _ "$MONITOR"
	[ "$status" -eq 0 ]
	[ "$output" = "true|" ]
}

@test "--watch dengan nilai numerik menyimpan interval" {
	run bash -c 'source "$1"; parse_args --watch 0.5; printf "%s|%s" "$WATCH" "$CLI_WATCH_INTERVAL"' _ "$MONITOR"
	[ "$status" -eq 0 ]
	[ "$output" = "true|0.5" ]
}

@test "--watch diikuti opsi lain tidak menelan opsi tersebut" {
	run bash -c 'source "$1"; parse_args --watch -t 90; printf "%s|%s|%s" "$WATCH" "$CLI_WATCH_INTERVAL" "$CLI_THRESHOLD"' _ "$MONITOR"
	[ "$status" -eq 0 ]
	[ "$output" = "true||90" ]
}

@test "--watch=abc ditolak" {
	run bash "$MONITOR" --watch=abc
	[ "$status" -eq 2 ]
	[[ "$output" == *"MONITOR_WATCH_INTERVAL"* ]]
}

@test "--watch 0 ditolak" {
	run bash "$MONITOR" --watch 0
	[ "$status" -eq 2 ]
	[[ "$output" == *"lebih besar dari 0"* ]]
}

@test "MONITOR_WATCH_INTERVAL=0 ditolak" {
	export MONITOR_WATCH_INTERVAL=0
	run bash "$MONITOR" --watch
	[ "$status" -eq 2 ]
	[[ "$output" == *"lebih besar dari 0"* ]]
}

@test "--watch tidak dapat digabung dengan --json" {
	run bash "$MONITOR" --watch --json
	[ "$status" -eq 2 ]
	[[ "$output" == *"tidak dapat digabung"* ]]
}
