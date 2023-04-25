#!/bin/bash

bats() {
	local tag_args=()
	if (($# > 1)); then
		tag_args+=(--filter-tags "$1")
		shift
	fi
	./bats-core/bin/bats -T --print-output-on-failure "$@" "${tag_args[@]}"
}
