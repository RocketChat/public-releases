#!/bin/bash

load "../common.bash"

bats_require_minimum_version 1.5.0

run_basic_mongodb_tests() {
	local tmppath
	tmppath="$(mktemp -d)"
	mongod --dbpath "$tmppath" --storageEngine wiredTiger &
	local mongod_pid="$!"
	sleep 10
	run get_current_mongodb_storage_engine
	assert_output "wiredTiger"
	run get_current_mongodb_version
	assert_output "4.4"
	kill -SIGINT "$mongod_pid"
	rm -rf "$tmppath"
}

overwrite_functions() {
	INFO() {
		:
	}
	DEBUG() {
		:
	}
	SUCCESS() {
		:
	}
	FATAL() {
		printf "%s" "$*" >&2
	}
	ERROR() {
		printf "%s" "$*" >&2
	}
	WARN() {
		:
	}
	funcrun() {
		"$@"
	}
	funcreturn() {
		printf "%s" "$*"
	}
	export -f INFO
	export -f DEBUG
	export -f SUCCESS
	export -f FATAL
	export -f ERROR
	export -f WARN
	export -f funcrun
	export -f funcreturn
}

setup_file() {
	# needed for all imports to work
	find install.sh -type f -execdir sed -Ei 's/^source /__source /g' {} \;
	__source() {
		# shellcheck disable=1090
		source install.sh"${1#"$(dirname "$(realpath "$0")")"}"
	}
	export TEST_MODE=true
	__source "$(dirname "$(realpath "$0")")"/lib/mongodb.bash
	for func in $(declare -F | awk '{ print $NF }'); do
		export -f "${func?}"
	done
	overwrite_functions
}

@test "Should install m" {
	run_and_assert_success _install_m
	assert_dir_exists "$output"
	assert_file_executable "$(path_join "$output" "m")"
	path_append "$output"
	assert command -v m
}

@test "Should install mongodb using m" {
	path_append "$HOME/.local/bin"
	run_and_assert_success _m_install_mongodb 4.4.0
	local m_path="${lines[$((${#lines[@]} - 1))]}"
	assert_dir_exists "$m_path"
	#local bins=(mongo mongod mongodump mongorestore mongoexport mongoimport)
	local bins=(mongo mongod)
	local binary
	for binary in "${bins[@]}"; do assert_file_executable "$(path_join "$m_path" "$binary")"; done
	(
		path_append "$m_path"
		run_basic_mongodb_tests
	)
}

@test "Should install mongodb manually fine" {
	run_and_assert_success _manual_install_mongodb 4.4.0
	local mongodb_path="${lines[$((${#lines[@]} - 1))]}"
	assert_dir_exists "$mongodb_path" # technically this is /usr/bin or /usr/sbin; just making sure that the function is not returning something wrong
	run_basic_mongodb_tests
}

teardown_file() {
	# cleanup
	run_and_assert_success pkm remove --autoremove -y mongodb-org
	run_and_assert_success rm /usr/share/keyrings/mongodb-org-4.4/gpg /etc/apt/sources.list.d/mongodb-org-4.4.list
	run_and_assert_success rm -rf ~/.local/m ~/.local/bin/*
}
