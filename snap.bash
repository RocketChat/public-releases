#!/bin/bash

bats() {
	local tags="$1"
	shift
	./bats-core/bin/bats -T --print-output-on-failure --filter-tags "$tags" "$@"
}

bats pre ./snap/tests.bats
bats 'pre,post' ./api_basic/api.bats
bats post ./snap/tests.bats
