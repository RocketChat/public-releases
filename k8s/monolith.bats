#!/bin/bash

load "bats-detik/lib/utils"
load "bats-detik/lib/linter"

load "../common.bash"

export DETIK_CLIENT_NAME="kubectl"
export DETIK_CLIENT_NAMESPACE="helm-bats-monolith"

setup_file() {
	export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-helm-bats}"
}

@test "verify assertions" {
	local file=
	[[ "$(basename "$PWD")" == "k8s" ]] && file="$(basename "$0")" || file="k8s/$(basename "$0")"
	run_and_assert_success lint "$file"
}

@test "lint chart" {
	run_and_assert_success helm lint ./rocketchat
}

@test "verify chart --dry-run" {
	run_and_assert_success bash -c '
		helm template ./rocketchat \
			--set "mongodb.auth.rootPassword=root" \
			--set "mongodb.auth.passwords={rocketchat}" \
			--set "mongodb.auth.usernames={rocketchat}" \
			--set "mongodb.auth.databases={rocketchat}" | kubectl apply --dry-run=client -f -
	'
}

@test "package chart" {
	run_and_assert_success helm package ./rocketchat
	assert [ -f "./rocketchat-${ROCKETCHAT_TAG}.tgz" ]
}

@test "actual deployment" {
	run_and_assert_success helm install "$DEPLOYMENT_NAME" --namespace "$DETIK_CLIENT_NAMESPACE" --create-namespace \
		--set "mongodb.auth.rootPassword=root" \
		--set "mongodb.auth.passwords={rocketchat}" \
		--set "mongodb.auth.usernames={rocketchat}" \
		--set "mongodb.auth.databases={rocketchat}" "./rocketchat-${ROCKETCHAT_TAG}.tgz"
}

@test "services are up" {
	run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-mongodb-headless'"
	run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-rocketchat'"
}

@test "deployments are up" {
	run_and_assert_success verify "there is 1 deployment named '${DEPLOYMENT_NAME}-rocketchat'"
}

@test "individual pods exist" {
	run_and_assert_success try "at most 5 times every 10s to find 1 pod named '${DEPLOYMENT_NAME}-mongodb-0' with 'status' being 'running'"
	run_and_assert_success try "at most 5 times every 10s to find 1 pod named '${DEPLOYMENT_NAME}-rocketchat-.+' with 'status' being 'running'"
}
