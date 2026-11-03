#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
	# shellcheck source=/dev/null
	source "$MONITOR"
}

@test "cpu_percent_from_samples: idle penuh menghasilkan 0" {
	run cpu_percent_from_samples \
		"0 0 0 0 0 0 0 0" \
		"0 0 0 100 0 0 0 0"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
}

@test "cpu_percent_from_samples: hitungan sibuk dibulatkan" {
	# total naik 900, idle naik 700 -> 200/900 = 22%
	run cpu_percent_from_samples \
		"100 0 100 800 0 0 0 0" \
		"200 0 200 1500 0 0 0 0"
	[ "$status" -eq 0 ]
	[ "$output" = "22" ]
}

@test "cpu_percent_from_samples: iowait dihitung sebagai idle" {
	# total naik 100, idle+iowait naik 100 -> 0%
	run cpu_percent_from_samples \
		"0 0 0 0 0 0 0 0" \
		"0 0 0 50 50 0 0 0"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
}

@test "cpu_percent_from_samples: sampel identik dianggap error" {
	run cpu_percent_from_samples \
		"100 0 100 800 0 0 0 0" \
		"100 0 100 800 0 0 0 0"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "cpu_percent_from_samples: sampel terlalu pendek dianggap error" {
	run cpu_percent_from_samples "1 2 3" "4 5 6"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "load_is_warning: membandingkan load dengan jumlah core" {
	run load_is_warning 2.0 2
	[ "$status" -eq 0 ]

	run load_is_warning 1.9 2
	[ "$status" -ne 0 ]

	run load_is_warning 0.5 1
	[ "$status" -ne 0 ]
}
