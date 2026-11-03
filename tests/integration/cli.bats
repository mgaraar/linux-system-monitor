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
