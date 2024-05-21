#!/bin/bash

load "../bats-detik/lib/utils"
load "../bats-detik/lib/detik"

load "../common.bash"

export DETIK_CLIENT_NAME="kubectl"
export DETIK_CLIENT_NAMESPACE="helm-bats-monolith"

# export DEBUG_DETIK="true"

setup_file() {
	export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-helm-bats}"
	export ROCKETCHAT_HOST
	export ROCKETCHAT_TAG
	export ROCKETCHAT_CHART_DIR
	export HELM_TAG="${HELM_TAG:-$ROCKETCHAT_TAG}"
	export ROCKETCHAT_CHART_ARCHIVE="${ROCKETCHAT_CHART_DIR%/}/rocketchat-${HELM_TAG}.tgz"

	export BATS_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/batsXXXXXXXXX")"
}

# bats test_tags=pre
@test "verify dependency install" {
	if [[ -d "${ROCKETCHAT_CHART_DIR%/}/charts" ]]; then
		skip "dependencies already downloaded"
	fi
	run_and_assert_success helm dependency update "$ROCKETCHAT_CHART_DIR"
}

# bats test_tags=pre
@test "lint chart" {
	run_and_assert_success helm lint "$ROCKETCHAT_CHART_DIR"
}

# bats test_tags=pre
@test "verify chart --dry-run" {
	run_and_assert_success bash -c "
		helm template $ROCKETCHAT_CHART_DIR \
			--set 'image.tag=$ROCKETCHAT_TAG' \
			--set 'mongodb.auth.rootPassword=root' \
			--set 'mongodb.auth.passwords={rocketchat}' \
			--set 'mongodb.auth.usernames={rocketchat}' \
			--set 'mongodb.auth.databases={rocketchat}' \
			--set 'federation.enabled=true' \
			--set 'ingress.federation.serveWellKnown=true' | kubectl apply --dry-run=client -f -
	"
}

# bats test_tags=pre
@test "verify packaging chart" {
	if [[ -f "$ROCKETCHAT_CHART_ARCHIVE" ]]; then
		skip "chart package already exists"
	fi
	run_and_assert_success helm package --app-version "$ROCKETCHAT_TAG" --version "$HELM_TAG" "$ROCKETCHAT_CHART_DIR" -d "$(dirname "$ROCKETCHAT_CHART_ARCHIVE")"
	assert [ -f "$ROCKETCHAT_CHART_ARCHIVE" ]
}

# bats test_tags=post
@test "install previous version" {
	run_and_assert_success helm upgrade --install "$DEPLOYMENT_NAME" rocketchat \
		--namespace "$DETIK_CLIENT_NAMESPACE" --create-namespace \
		--set "mongodb.auth.rootPassword=root" \
		--set "mongodb.auth.passwords={rocketchat}" \
		--set "mongodb.auth.usernames={rocketchat}" \
		--set "mongodb.auth.databases={rocketchat}" \
		--set "ingress.enabled=true" \
		--set "prometheusScraping.enabled=true" \
		--set "prometheusScraping.port=9148" \
		--set "host=$ROCKETCHAT_HOST" \
		--set "federation.enabled=true" \
		--repo https://rocketchat.github.io/helm-charts
}

# bats test_tags=post
@test "verify federation secrets are non empty" {
	#mostly to save the values
	local \
		as_token hs_token appservice_id

	as_token="$(\kubectl -n $DETIK_CLIENT_NAMESPACE get secret "$DEPLOYMENT_NAME"-rocketchat-synapse --template='{{.data.as_token}}')" # intentionally kept encoded
	hs_token="$(\kubectl -n $DETIK_CLIENT_NAMESPACE get secret "$DEPLOYMENT_NAME"-rocketchat-synapse --template='{{.data.hs_token}}')"
	appservice_id="$(\kubectl -n $DETIK_CLIENT_NAMESPACE get secret "$DEPLOYMENT_NAME"-rocketchat-synapse --template='{{.data.appservice_id}}')"

	refute [ "$as_token" = "" ]
	refute [ "$hs_token" = "" ]
	refute [ "$appservice_id" = "" ]

	echo "# saving secret values to recheck later" >&3

	jo as_token="$as_token" hs_token="$hs_token" appservice_id="$appservice_id" > "$BATS_TMPDIR/synapse_secrets.json"

	assert test -f "$BATS_TMPDIR/synapse_secrets.json"
}

# bats test_tags=post
@test "verify upgrade to local chart" {
	run_and_assert_success helm upgrade "$DEPLOYMENT_NAME" --namespace "$DETIK_CLIENT_NAMESPACE" \
		--set "image.tag=$ROCKETCHAT_TAG" \
		--set "mongodb.auth.rootPassword=root" \
		--set "mongodb.auth.passwords={rocketchat}" \
		--set "mongodb.auth.usernames={rocketchat}" \
		--set "mongodb.auth.databases={rocketchat}" \
		--set "ingress.enabled=true" \
		--set "prometheusScraping.enabled=true" \
		--set "prometheusScraping.port=9148" \
		--set "host=$ROCKETCHAT_HOST" \
		--set "federation.enabled=true" \
		"$ROCKETCHAT_CHART_ARCHIVE"
}

# bats test_tags=pre
@test "verify the chart actually installs" {
	if [[ -n $(helm ls -n "$DETIK_CLIENT_NAMESPACE" -l "name=$DEPLOYMENT_NAME" --no-headers -q) ]]; then
		skip "same release with name already installed"
	fi

	run_and_assert_success helm install "$DEPLOYMENT_NAME" --namespace "$DETIK_CLIENT_NAMESPACE" --create-namespace \
		--set "image.tag=$ROCKETCHAT_TAG" \
		--set "mongodb.auth.rootPassword=root" \
		--set "mongodb.auth.passwords={rocketchat}" \
		--set "mongodb.auth.usernames={rocketchat}" \
		--set "mongodb.auth.databases={rocketchat}" \
		--set "ingress.enabled=true" \
		--set "prometheusScraping.enabled=true" \
		--set "prometheusScraping.port=9148" \
		--set "federation.enabled=true" \
		--set "host=$ROCKETCHAT_HOST" \
		"$ROCKETCHAT_CHART_ARCHIVE"
}

# bats test_tags=pre,post
@test "verify all services are up" {
	run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-mongodb-headless$'"
	run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-rocketchat$'"
	run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-rocketchat-bridge'"
	run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-rocketchat-synapse'"
}

# bats test_tags=pre,post
@test "verify all deployments are up" {
	run_and_assert_success verify "there is 1 deployment named '${DEPLOYMENT_NAME}-rocketchat$'"
	run_and_assert_success verify "there is 1 deployment named '${DEPLOYMENT_NAME}-rocketchat-synapse'"
}

# bats test_tags=pre,post
@test "verify all individual pods exist" {
	run_and_assert_success try "at most 5 times every 30s to find 1 pod named '${DEPLOYMENT_NAME}-mongodb-0' with 'status' being 'running'"
	run_and_assert_success try "at most 5 times every 30s to find 2 pods named '^${DEPLOYMENT_NAME}-rocketchat-' with 'status' being 'running'"
	run_and_assert_success try "at most 5 times every 30s to find 1 pods named '^${DEPLOYMENT_NAME}-rocketchat-synapse-' with 'status' being 'running'"
}

# bats test_tags=pre,post
@test "verify all endpoints' configs" {
	run_and_assert_success try at most 5 times every 30s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-mongodb-headless'" \
		with "'.subsets[0].ports[0].port'" being "'27017'"

	run_and_assert_success try at most 5 times every 30s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat'" \
		with "'subsets[*].ports[*].name'" matching "'metrics,http|http,metrics'"

	run_and_assert_success try at most 5 times every 30s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat'" \
		with "'subsets[*].ports[*].port'" matching "'9148,3000|3000,9148'"

	try at most 5 times every 30s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat-bridge'" \
		with "'subsets[*].ports[*].port'" being "'3300'"

	try at most 5 times every 30s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat-synapse'" \
		with "'subsets[*].ports[*].port'" being "'8008'"
}

# bats test_tags=pre,post
@test "verify ingress config" {
	verify "'.spec.rules[0].host'" is "'$ROCKETCHAT_HOST'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	verify "'.spec.rules[*].http.paths[*].backend.service.name'" is "'${DEPLOYMENT_NAME}-rocketchat,${DEPLOYMENT_NAME}-rocketchat-synapse'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	verify "'.spec.rules[*].http.paths[*].backend.service.port.name'" is "'http,http'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	verify "'.spec.rules[*].http.paths[*].path'" is "'/,/'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	run_and_assert_success verify "'.spec.rules[*].http.paths[*].pathType'" is "'Prefix,Prefix'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
}

# bats test_tags=pre,post
@test "verify secret resources and their values" {
	export DETIK_CASE_INSENSITIVE_PROPERTIES="false"
	# regex matching is must for strict verification
	# otherwie base64 values won't match
	local \
		root_password="$(printf "root" | base64)" \
		password="$(printf "rocketchat" | base64)"

	debug "password=$password"

	verify "'.data.mongodb-passwords'" matches "'^$password\$'" \
		for secret named "'${DEPLOYMENT_NAME}-mongodb'"
	verify "'.data.mongodb-root-password'" matches "'^$root_password\$'" \
		for secret named "'${DEPLOYMENT_NAME}-mongodb'"

	local \
		mongo_uri="$(printf "mongodb://rocketchat:rocketchat@%s-mongodb-headless:27017/rocketchat?replicaSet=rs0" "$DEPLOYMENT_NAME" | base64)" \
		mongo_oplog_uri="$(printf "mongodb://root:root@%s-mongodb-headless:27017/local?replicaSet=rs0&authSource=admin" "$DEPLOYMENT_NAME" | base64)"
	verify "'.data.mongo-uri'" matches "'^$mongo_uri\$'" \
		for secret named "'${DEPLOYMENT_NAME}-rocketchat[^-]'"
	verify "'.data.mongo-oplog-uri'" matches "'^$mongo_oplog_uri\$'" \
		for secret named "'${DEPLOYMENT_NAME}-rocketchat[^-]'"
}

# bats test_tags=post
@test "verify federation secrets are unchanged post-upgrade/reapply" {
	# federation secret
	local \
		as_token hs_token appservice_id

	assert test -f  "$BATS_TMPDIR/synapse_secrets.json"

	as_token="$(jq -r .as_token "$BATS_TMPDIR/synapse_secrets.json")"
	hs_token="$(jq -r .hs_token "$BATS_TMPDIR/synapse_secrets.json")"
	appservice_id="$(jq -r .appservice_id "$BATS_TMPDIR/synapse_secrets.json")"

	verify "'.data.as_token'" matches "'^$as_token\$'" \
		for secret named "'${DEPLOYMENT_NAME}-rocketchat-synapse'"
	verify "'.data.hs_token'" matches "'^$hs_token\$'" \
		for secret named "'${DEPLOYMENT_NAME}-rocketchat-synapse'"
	verify "'.data.appservice_id'" matches "'^$appservice_id\$'" \
		for secret named "'${DEPLOYMENT_NAME}-rocketchat-synapse'"
}

# bats test_tags=pre,post
@test "verify configmap resources exist" {
	run_and_assert_success verify "there is 1 configmap named 'rocketchat-mongodb-fix-clustermonitor-role-configmap'"
	run_and_assert_success verify "there is 1 configmap named '${DEPLOYMENT_NAME}-rocketchat-scripts'"
}

# bats test_tags=post
@test "verify uninstalling rocketchat chart" {
	run_and_assert_success helm uninstall "$DEPLOYMENT_NAME" -n "$DETIK_CLIENT_NAMESPACE"
	run_and_assert_success kubectl delete namespace "$DETIK_CLIENT_NAMESPACE"
}

teardown_file() {
	rm -rf $BATS_TMPDIR
}
