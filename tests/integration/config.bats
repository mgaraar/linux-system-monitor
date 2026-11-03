#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
	install_default_fakes
	CONFIG_FILE="$BATS_TEST_TMPDIR/config.sh"
	printf 'MONITOR_THRESHOLD=10\n' >"$CONFIG_FILE"
}

@test "nilai dari config file dipakai" {
	run bash "$MONITOR" --config "$CONFIG_FILE"
	[ "$status" -eq 1 ]
	[[ "$output" == *"DISK  : WARNING - 20%"* ]]
}

@test "environment menang atas config file" {
	export MONITOR_THRESHOLD=90

	run bash "$MONITOR" --config "$CONFIG_FILE"
	[ "$status" -eq 0 ]
	[[ "$output" == *"DISK  : NORMAL - 20%"* ]]
}

@test "argumen CLI menang atas config file" {
	run bash "$MONITOR" --config "$CONFIG_FILE" -t 90
	[ "$status" -eq 0 ]
	[[ "$output" == *"DISK  : NORMAL - 20%"* ]]
}

@test "MONITOR_CONFIG juga memuat file konfigurasi" {
	export MONITOR_CONFIG="$CONFIG_FILE"

	run bash "$MONITOR"
	[ "$status" -eq 1 ]
}

@test "config file dengan nilai invalid ditolak" {
	printf 'MONITOR_THRESHOLD=0\n' >"$CONFIG_FILE"

	run bash "$MONITOR" --config "$CONFIG_FILE"
	[ "$status" -eq 2 ]
	[[ "$output" == *"threshold"* ]]
}
