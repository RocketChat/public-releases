#! /usr/bin/env bash

load "../common.bash"

setup_file() {
	echo "# Waiting for server to start up" >&3
	wait_for_server
	if [[ -z "$SKIP_REGISTRATION" ]]; then
		echo "# Registering admin dummy user" >&3
		register
	else
		echo "# Skipping user registration" >&3
	fi
	echo "# Logging into admin account" >&3
	login
}

# bats test_tags=post
@test "Should return the correct release tag" {
	assert_not_equal "$ROCKETCHAT_TAG"
	run curl \
		-H "x-auth-token: $AUTH_TOKEN" \
		-H "x-user-id: $USER_ID" \
		-H 'content-type: application/json' \
		-s "${HOST}/api/info"
	assert_success
	assert_field_equal info version "$ROCKETCHAT_TAG"
	return 0
}

# bats test_tags=post,pre
@test "Should be able to see user list" {
	get users.list
	assert_field_equal total 2
}

# bats test_tags=post,pre
@test "Should be able to send a message to GENERAL" {
	post chat.sendMessage message= "rid=GENERAL msg=HelloWorld"
}

# bats test_tags=post,pre
@test "Should be able to read the last sent message" {
	get channels.messages roomId=GENERAL
	assert_field_equal messages 0 msg "HelloWorld"
}

teardown_file() {
	echo "# Logging out" >&3
	logout
}
