#!/bin/bash

load "../common.bash"

bats_require_minimum_version 1.5.0

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
	__source "$(dirname "$(realpath "$0")")"/lib/nodejs.bash
	for func in $(declare -F | awk '{ print $NF }'); do
		export -f "${func?}"
	done
	overwrite_functions
}

@test "Should fail to install n" {
	run_and_assert_failure _install_n
}

@test "Should install nodejs fine manually" {
	run_and_assert_success --separate-stderr _manual_install_nodejs 16.0.0 /opt/nodejs
	assert_dir_exists /opt/nodejs
	assert_dir_exists "$output"
	path_append "$output"
	assert node_confirm_version "^v16"
}

@test "Should install nvm" {
	# for the alias, can't run it by run
	run_and_assert_success _install_nvm /opt/nvm
	assert_dir_exists /opt/nvm
	assert_file_exists /opt/nvm/nvm.sh
}

@test "Should install nodejs using nvm" {
	export _BASH_ENV="/opt/nvm/nvm.sh"
	run_and_assert_success --separate-stderr _nvm_install_nodejs 14.19.3 # arbitrary version string
	local node_path="${lines[$((${#lines[@]} - 1))]}"
	assert_dir_exists "$node_path"
	path_append "$node_path"
	assert command -v node
	assert node_confirm_version "v14.19.3"
}

@test "Should install n successfully" {
	export _BASH_ENV="/opt/nvm/nvm.sh"
	run_and_assert_success nvm which 14.19.3
	local node_path="$(dirname "$output")"
	path_append "$node_path"
	run_and_assert_success _install_n
	assert command -v n
}

@test "Should install nodejs with n successfully" {
	export _BASH_ENV="/opt/nvm/nvm.sh"
	run_and_assert_success nvm which 14.19.3
	local n_path="$(dirname "$output")"
	path_append "$n_path"
	run_and_assert_success --separate-stderr _n_install_nodejs 14.18.3 # arbitrary version string
	local node_path="${lines[$((${#lines[@]} - 1))]}"
	assert_dir_exists "$node_path"
	path_append "$node_path"
	assert command -v node
	assert node_confirm_version "v14.18.3"
}

@test "Should install nodejs from scratch using nvm" {
	use_nvm() { true; }
	use_n() { false; }
	run_and_assert_success install_nodejs 16
	assert_dir_exists /opt/nvm
	assert_file_exists /opt/nvm/nvm.sh
	local node_path="${lines[$((${#lines[@]} - 1))]}"
	assert_dir_exists "$node_path" # nvm node path
	assert_file_executable "$(path_join "$node_path" "node")"
	path_append "$node_path"
	assert node_confirm_version "^v16"
}

teardown_file() {
	run_and_assert_success rm -rf /opt/nvm
}
