#!/bin/bash

load "../common.bash"

# FIXME add all other command files like upgrade doctor etc
@test "Should have all command files" {
	assert_file_exists "install.sh/commands/install.bash"
}

@test "Should have all helper files" {
	local file
	local files=(
		"host.bash"
		"lib.bash"
		"mongodb.bash"    # NOTE imp
		"rocketchat.bash" # NOTE imp
		"nodejs.bash"     # NOTE imp
	)
	for file in "${files[@]}"; do assert_file_exists "./install.sh/helpers/$file"; done
}

@test "Should have the primary files" {
	assert_file_exists "./install.sh/main.bash"
	assert_file_exists "./install.sh/rocketchatctl"
	assert_file_exists "./install.sh/install.sh"
}

@test "Main scripts must be executable" {
	assert_file_executable "./install.sh/rocketchatctl"
	assert_file_executable "./install.sh/main.bash"
	assert_file_executable "./install.sh/install.sh"
}
