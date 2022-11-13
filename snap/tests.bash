#!/bin/bash

load "../common.bash"

# bats test_tags=pre
@test "Should install previous stable version" {
	run sudo snap install rocketchat-server --stable
	assert_success
}

# bats test_tags=post
@test "Should upgrade to new snap dangerously" {
	assert_not_equal "$ROCKETCHAT_SNAP"
	run sudo snap install "$ROCKETCHAT_SNAP" --dangerous
	assert_success
}

