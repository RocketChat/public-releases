#!/bin/bash

load "../bats-assert/load.bash"
load "../bats-support/load.bash"
load "../bats-file/load.bash"

readonly HOST="http://localhost:3000"
readonly EMAIL="dummy@nonexistent.email"
readonly REALNAME="Dummy User"
readonly USERNAME="dummy.user"
readonly PASSWORD="dummypassword1234"

api() {
	printf "$HOST/api/v1/%s" "${1?path required}"
}

wait_for_server() {
	local max_attempts="${ROCKETCHAT_MAX_ATTEMPTS:-50}"
	local counter=0

	until curl --connect-timeout 5 --output /dev/null --silent --head --fail $HOST; do
		((counter >= max_attempts)) && fail "timeout reached, couldn't connect to Rocket.Chat"
		counter=$((counter + 1))
		sleep 1
	done
}

_json_array() {
	# @description generate json arg array
	# shellcheck disable=2206
	local args=(${1//=/ }) # [0]=key [1]=values
	local _IFS=$IFS
	IFS=,
	local members=()
	for member in ${args[1]}; do
		members+=("$member")
	done
	IFS=$_IFS
	printf "%s=%s" "${args[0]}" "$(jo -a "${members[@]}")"
}

_is_simple_assignment() {
	[[ $1 =~ .+=[^,]+$ ]]
}

_is_nested_assignment() {
	[[ $1 =~ .+=$ ]]
}

_is_array_assignment() {
	[[ $1 =~ , ]]
}

_build_json_from_args() {
	local jo_args=()
	while [[ -n "$1" ]]; do
		if _is_simple_assignment "$1"; then
			jo_args+=("$1")
			shift
		fi
		if _is_array_assignment "$1"; then
			jo_args+=("$(_json_array "$1")")
			shift
		fi
		# more than two levels of nesting doesn't work with this
		# because of shell quoting issues
		# FIXME
		if _is_nested_assignment "$1"; then
			# shellcheck disable=2086
			jo_args+=("${1}$(_build_json_from_args $2)")
			shift 2
		fi
	done
	#((${#jo_args[@]} == 1)) && echo "${jo_args[@]}" || jo "${jo_args[@]}"
	jo "${jo_args[@]}"
}

_query() {
	local query="?"
	for param in "$@"; do
		query+="${param}&"
	done
	echo "${query:0:$((${#query} - 1))}"
}

get() {
	local curl_args=(
		--silent
		-H
		"x-auth-token: $AUTH_TOKEN"
		-H
		"x-user-id: $USER_ID"
		-H
		"content-type: application/json"
	)
	local endpoint
	endpoint="$(api "${1?endpoint required}")"
	shift
	local query
	query="$(_query "$@")"
	curl_args+=(
		"${endpoint}${query}"
	)
	run curl "${curl_args[@]}"
	assert_success
	assert_api_success
	assert_equal "$?" 0
}

post() {
	local curl_args=(
		--silent
		-H
		"x-auth-token: $AUTH_TOKEN"
		-H
		"x-user-id: $USER_ID"
		-H
		"content-type: application/json"
	)
	local endpoint
	endpoint="$(api "${1?endpoint required}")"
	curl_args+=("$endpoint")
	shift
	local body
	((${#@} > 0)) && body="$(_build_json_from_args "$@")"
	curl_args+=(
		-d
		"$body"
	)
	run curl "${curl_args[@]}"
	assert_success
	assert_api_success
	assert_equal "$?" 0
}

register() {
	post users.register username="$USERNAME" email="$EMAIL" pass="$PASSWORD" name="$REALNAME"
}

login() {
	post login user="$USERNAME" password="$PASSWORD"
	export AUTH_TOKEN="$(jq .data.authToken -r <<<"$output")"
	export USER_ID="$(jq .data.userId -r <<<"$output")"
}

logout() {
	post logout
}

_is_number() {
	[[ "$1" =~ ^[0-9]+$ ]]
}

_needs_square_brackets() {
	! [[ "$1" =~ ^[a-zA-Z_-]+$ ]]
}

assert_field_equal() {
	local to_check="${@: -1}"
	local check_string=
	set -- "${@:1:$(($# - 1))}"
	for arg in "$@"; do
		if _is_number "$arg"; then
			check_string+="[$arg]"
			continue
		fi
		if _needs_square_brackets "$arg"; then
			check_string+="[\"$arg\"]"
			continue
		fi
		check_string+=".${arg}"
	done
	assert_equal "$(jq "${check_string}" -r <<<"$output")" "$to_check"
}

assert_field_equal_raw() {
	assert_equal "$(jq "${1}" -r <<<"$output")" "$2"
}

assert_api_success() {
	assert [[ "$(jq .success -r <<<"$output")" == 'true' ]] || [[ "$(jq .status -r <<<"$output")" == 'success' ]]
}

run_and_assert_success() {
	run "$@"
	assert_success
}

run_and_assert_failure() {
	run "$@"
	assert_failure
}
