#!/usr/bin/env bats

load 'test_helper'

setup() {
	common_setup
	fake_ps_systemd
	fake_systemctl_default
	# shellcheck source=/dev/null
	source "$MONITOR"
}

@test "check_service: service aktif" {
	check_service ssh.service
	[ "$SERVICE_STATE" = "active" ]
	[ "$SERVICE_NAME_USED" = "ssh.service" ]
}

@test "check_service: service tidak aktif" {
	check_service inactive.service
	[ "$SERVICE_STATE" = "inactive" ]
	[ "$SERVICE_DETAIL" = "failed" ]
}

@test "check_service: service tidak ditemukan" {
	check_service missing.service
	[ "$SERVICE_STATE" = "not-found" ]
}

@test "check_service: systemd bukan PID 1 membuat status unavailable" {
	fake_ps_nonsystemd
	check_service ssh.service
	[ "$SERVICE_STATE" = "unavailable" ]
	[[ "$SERVICE_DETAIL" == *"PID 1"* ]]
}

@test "check_service: fallback untuk systemd lama tanpa --value" {
	write_fake systemctl 'if [[ " $* " == *" --value "* ]]; then
	exit 0
fi
case "$*" in
*LoadState*) echo "LoadState=loaded" ;;
*ActiveState*) echo "ActiveState=active" ;;
esac'
	check_service ssh.service
	[ "$SERVICE_STATE" = "active" ]
}

@test "check_service: status tidak terbaca menjadi unavailable" {
	write_fake systemctl 'exit 0'
	check_service ssh.service
	[ "$SERVICE_STATE" = "unavailable" ]
}
