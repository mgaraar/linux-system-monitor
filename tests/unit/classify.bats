#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
	# shellcheck source=/dev/null
	source "$MONITOR"
}

@test "classify: di bawah threshold adalah normal" {
	run classify 5 80
	[ "$status" -eq 0 ]
	[ "$output" = "normal" ]
}

@test "classify: sama dengan threshold adalah warning" {
	run classify 80 80
	[ "$output" = "warning" ]
}

@test "classify: di atas threshold adalah warning" {
	run classify 95 80
	[ "$output" = "warning" ]
}

@test "classify: nilai kosong adalah error" {
	run classify "" 80
	[ "$output" = "error" ]
}

@test "classify: nilai bukan angka adalah error" {
	run classify "12x" 80
	[ "$output" = "error" ]
}

@test "percent_text: angka menjadi persen" {
	run percent_text 50
	[ "$output" = "50%" ]
}

@test "percent_text: nilai tidak valid jadi teks fallback" {
	run percent_text "n/a"
	[ "$output" = "data tidak tersedia" ]
}

@test "json_percent: nilai angka" {
	run json_percent cpu 50 normal
	[ "$output" = '"cpu":{"value":50,"status":"normal"}' ]
}

@test "json_percent: nilai tidak valid menjadi null" {
	run json_percent ram "" error
	[ "$output" = '"ram":{"value":null,"status":"error"}' ]
}

@test "json_escape: tanda kutip dan backslash di-escape" {
	run json_escape 'a"b\c'
	[ "$output" = 'a\"b\\c' ]
}

@test "is_uint dan is_number membedakan format" {
	run is_uint 123
	[ "$status" -eq 0 ]

	run is_uint 1.5
	[ "$status" -ne 0 ]

	run is_number 1.5
	[ "$status" -eq 0 ]

	run is_number abc
	[ "$status" -ne 0 ]
}
