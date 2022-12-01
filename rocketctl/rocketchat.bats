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
	__source "$(dirname "$(realpath "$0")")"/lib/rocketchat.bash
	__source "$(dirname "$(realpath "$0")")"/lib/nodejs.bash
	for func in $(declare -F | awk '{ print $NF }'); do
		export -f "${func?}"
	done
	overwrite_functions
	export __state_file="$(mktemp)"
	trap "rm $__state_file" EXIT
	refresh_state() {
		source "$__state_file"
	}
	export -f refresh_state
}

@test "Should verify releases right" {
	run_and_assert_failure verify_release 4.9.0
	verify_release 5.0.0
	refute [ -z "$__RELEASE_INFO_JSON" ]
	refute [ -z "$__COMPATIBLE_MONGODB_VERSIONS_JSON" ]
	run printf "$__RELEASE_INFO_JSON"
	assert_field_equal tag 5.0.0
	assert_field_equal commit 59cae121081e16ed80c9b65db7c6c235a096d043
	assert_field_equal key "build/rocket.chat-5.0.0.tgz"
	assert_field_equal nodeVersion 14.19.3
	printf >"$__state_file" "export %s='%s'\nexport %s='%s'" \
		"__RELEASE_INFO_JSON" "$__RELEASE_INFO_JSON" \
		"__COMPATIBLE_MONGODB_VERSIONS_JSON" "$__COMPATIBLE_MONGODB_VERSIONS_JSON"
}

@test "Should download rocketchat archive fine" {
	refresh_state
	run_and_assert_success _download_rocketchat /tmp
	assert_file_exists "/tmp/$(_get_archive_file_name)"
}
