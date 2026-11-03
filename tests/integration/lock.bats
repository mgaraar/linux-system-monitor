#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
	install_default_fakes
	export MONITOR_LOCK_FILE="$BATS_TEST_TMPDIR/monitor.lock"
}

teardown() {
	wait || true
}

@test "run dilewati saat lock sedang dipegang" {
	flock -n "$MONITOR_LOCK_FILE" -c 'sleep 2' &
	sleep 0.2

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[[ "$output" == *"dilewati"* ]]
}

@test "lock dilepas setelah run selesai" {
	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[[ "$output" != *"dilewati"* ]]

	run bash "$MONITOR"
	[ "$status" -eq 0 ]
	[[ "$output" != *"dilewati"* ]]
}
