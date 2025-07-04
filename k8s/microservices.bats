#!/bin/bash

load "../bats-detik/lib/utils"
load "../bats-detik/lib/detik"

load "../common.bash"

export DETIK_CLIENT_NAME="kubectl"
export DETIK_CLIENT_NAMESPACE="helm-bats-microservices"

# export DEBUG_DETIK="true"

setup_file() {
	export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-helm-bats}"
	export ROCKETCHAT_HOST
	export ROCKETCHAT_TAG
	export ROCKETCHAT_CHART_DIR
	export HELM_TAG="${HELM_TAG:-$ROCKETCHAT_TAG}"
	export ROCKETCHAT_CHART_ARCHIVE="${ROCKETCHAT_CHART_DIR%/}/rocketchat-${HELM_TAG}.tgz"
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
			--set 'microservices.enabled=true' | kubectl apply --dry-run=client -f -
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
		--set "microservices.enabled=true" \
		--set "mongodb.auth.rootPassword=root" \
		--set "mongodb.auth.passwords={rocketchat}" \
		--set "mongodb.auth.usernames={rocketchat}" \
		--set "mongodb.auth.databases={rocketchat}" \
		--set "ingress.enabled=true" \
		--set "prometheusScraping.enabled=true" \
		--set "prometheusScraping.port=9148" \
		--set "host=$ROCKETCHAT_HOST" \
		--repo https://rocketchat.github.io/helm-charts
}

# bats test_tags=post
@test "verify upgrade to local chart" {
	run_and_assert_success helm upgrade "$DEPLOYMENT_NAME" --namespace "$DETIK_CLIENT_NAMESPACE" \
		--set "image.tag=$ROCKETCHAT_TAG" \
		--set "microservices.enabled=true" \
		--set "mongodb.auth.rootPassword=root" \
		--set "mongodb.auth.passwords={rocketchat}" \
		--set "mongodb.auth.usernames={rocketchat}" \
		--set "mongodb.auth.databases={rocketchat}" \
		--set "ingress.enabled=true" \
		--set "prometheusScraping.enabled=true" \
		--set "prometheusScraping.port=9148" \
		--set "host=$ROCKETCHAT_HOST" \
		"$ROCKETCHAT_CHART_ARCHIVE"
}

# bats test_tags=pre
@test "verify the chart actually installs" {
	run_and_assert_success helm install "$DEPLOYMENT_NAME" --namespace "$DETIK_CLIENT_NAMESPACE" --create-namespace \
		--set "image.tag=$ROCKETCHAT_TAG" \
		--set "microservices.enabled=true" \
		--set "mongodb.auth.rootPassword=root" \
		--set "mongodb.auth.passwords={rocketchat}" \
		--set "mongodb.auth.usernames={rocketchat}" \
		--set "mongodb.auth.databases={rocketchat}" \
		--set "ingress.enabled=true" \
		--set "prometheusScraping.enabled=true" \
		--set "prometheusScraping.port=9148" \
		--set "host=$ROCKETCHAT_HOST" \
		"$ROCKETCHAT_CHART_ARCHIVE"
}

# bats test_tags=pre,post
@test "verify all services are up" {
	run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-mongodb-headless'"
	local svc=
	for svc in presence authorization stream-hub account ddp-streamer; do
		run_and_assert_success verify "there is 1 service named '${DEPLOYMENT_NAME}-${svc}'"
	done
	run_and_assert_success verify "there are 2 service named '${DEPLOYMENT_NAME}-rocketchat'"
	# chart now manually creates the headless service at the time of installation
	run_and_assert_success verify "there are 2 services named '${DEPLOYMENT_NAME}-nats'"
}

# bats test_tags=pre,post
@test "verify all deployments are up" {
	local deploy=
	for deploy in nats-box rocketchat presence authorization stream-hub account ddp-streamer; do
		run_and_assert_success verify "there is 1 deployment named '${DEPLOYMENT_NAME}-${deploy}'"
	done
}

# bats test_tags=pre,post
@test "verify all individual pods exist" {
	run_and_assert_success try "at most 5 times every 30s to find 1 pod named '${DEPLOYMENT_NAME}-mongodb-0' with 'status' being 'running'"
	run_and_assert_success try "at most 5 times every 30s to find 1 pod named '${DEPLOYMENT_NAME}-nats-0' with 'status' being 'running'"
	local deploy=
	for deploy in nats-box rocketchat presence authorization stream-hub account ddp-streamer; do
		run_and_assert_success try "at most 5 times every 30s to find 1 pod named '^${DEPLOYMENT_NAME}-${deploy}-' with 'status' being 'running'"
	done
}

# bats test_tags=pre,post
@test "verify all endpoints' configs" {
	skip "This test needs improvements"
	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-mongodb-headless'" \
		with "'.subsets[0].ports[0].port'" being "'27017'"

	local deploy=
	for deploy in presence authorization stream-hub account; do
		run_and_assert_success try at most 5 times every 10s \
			to find 1 ep named "'${DEPLOYMENT_NAME}-${deploy}'" \
			with "'.subsets[0].ports[0].name'" being "'metrics'"
		run_and_assert_success try at most 5 times every 10s \
			to find 1 ep named "'${DEPLOYMENT_NAME}-${deploy}'" \
			with "'.subsets[0].ports[0].port'" being "'9458'"
	done

	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-ddp-streamer'" \
		with "'.subsets[*].ports[*].name'" matching "'metrics,http|http,metrics'"

	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-ddp-streamer'" \
		with "'.subsets[*].ports[*].port'" matching "'9458,3000|3000,9458'"

	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat$'" \
		with "'.subsets[*].ports[*].name'" matching "'metrics'"
	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat$'" \
		with "'.subsets[*].ports[*].port'" matching "'9148'"

	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat$'" \
		with "'.subsets[*].ports[*].name'" matching "'http'"
	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat$'" \
		with "'.subsets[*].ports[*].port'" matching "'3000'"

	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat$'" \
		with "'.subsets[*].ports[*].name'" matching "'moleculer-metrics'"
	run_and_assert_success try at most 5 times every 10s \
		to find 1 ep named "'${DEPLOYMENT_NAME}-rocketchat$'" \
		with "'.subsets[*].ports[*].port'" matching "'9458'"

	# unfortunately can't do it like this, because of how detik gets these informations
	# local idx=
	# for idx in 0 1 2; do
	# run try at most 1 times every 1s \
	# 	to find 1 ep named "'${deployment_name}-rocketchat'" \
	# 	with "'.subsets[0].ports[$idx].name'" being "'metrics'"
	# 	if ((status == 0)); then
	# 		run_and_assert_success try at most 5 times every 10s \
	# 			to find 1 ep named "'${deployment_name}-rocketchat'" \
	# 			with "'.subsets[0].ports[$idx].port'" being "'9148'"
	# 		continue
	# 	fi

	# 	run try at most 1 times every 1s \
	# 		to find 1 ep named "'${deployment_name}-rocketchat'" \
	# 		with "'.subsets[0].ports[$idx].name'" being "'http'"
	# 	if ((status == 0)); then
	# 		run_and_assert_success try at most 5 times every 10s \
	# 			to find 1 ep named "'${deployment_name}-rocketchat'" \
	# 			with "'.subsets[0].ports[$idx].port'" being "'3000'"
	# 		continue
	# 	fi

	# 	run try at most 1 times every 1s \
	# 		to find 1 ep named "'${deployment_name}-rocketchat'" \
	# 		with "'.subsets[0].ports[$idx].name'" being "'moleculer-metrics'"
	# 	if ((status == 0)); then
	# 		run_and_assert_success try at most 1 times every 1s \
	# 			to find 1 ep named "'${deployment_name}-rocketchat'" \
	# 			with "'.subsets[0].ports[$idx].port'" being "'9458'"
	# 		continue
	# 	fi

	# 	fail "unknown endpoint"
	# done
}

# bats test_tags=pre,post
@test "verify ingress config" {
	run_and_assert_success verify "'.spec.rules[0].host'" is "'$ROCKETCHAT_HOST'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	run_and_assert_success verify "'.spec.rules[*].http.paths[*].pathType'" is "'Prefix,Prefix,Prefix'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	run_and_assert_success verify "'.spec.rules[*].http.paths[*].backend.service.name'" matches "'${DEPLOYMENT_NAME}-rocketchat'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	run_and_assert_success verify "'.spec.rules[*].http.paths[*].backend.service.name'" matches "'${DEPLOYMENT_NAME}-rocketchat'" \
		for ingress named "'${DEPLOYMENT_NAME}-ddp-streamer'"

	run_and_assert_success verify "'.spec.rules[*].http.paths[*].backend.service.port.name'" is "'http,http,http'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	run_and_assert_success verify "'.spec.rules[*].http.paths[*].path'" matches "'/'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	run_and_assert_success verify "'.spec.rules[*].http.paths[*].path'" matches "'/sockjs'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	run_and_assert_success verify "'.spec.rules[*].http.paths[*].path'" matches "'/websocket'" \
		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	# local idx=
	# for idx in 0 1 2; do
	# 	run verify "'.spec.rules[0].http.paths[$idx].path'" is "'/'" \
	# 		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	# 	if ((status == 0)); then
	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].backend.service.port.name'" is "'http'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].pathType'" is "'Prefix'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].backend.service.name'" is "'${DEPLOYMENT_NAME}-rocketchat'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	# 		continue
	# 	fi

	# 	run verify "'.spec.rules[0].http.paths[$idx].path'" is "'/sockjs'" \
	# 		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	# 	if ((status == 0)); then
	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].backend.service.port.name'" is "'http'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].pathType'" is "'Prefix'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].backend.service.name'" is "'${DEPLOYMENT_NAME}-ddp-streamer'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	# 		continue
	# 	fi

	# 	run verify "'.spec.rules[0].http.paths[$idx].path'" is "'/websocket'" \
	# 		for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	# 	if ((status == 0)); then
	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].backend.service.port.name'" is "'http'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].pathType'" is "'Prefix'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"

	# 		run_and_assert_success verify "'.spec.rules[$idx].http.paths[$idx].backend.service.name'" is "'${DEPLOYMENT_NAME}-ddp-streamer'" \
	# 			for ingress named "'${DEPLOYMENT_NAME}-rocketchat'"
	# 		continue
	# 	fi

	# 	fail "unknown ingress rule"
	# done
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
	run_and_assert_success verify "'.data.mongodb-passwords'" matches "'^$password\$'" \
		for secret named "'${DEPLOYMENT_NAME}-mongodb'"
	run_and_assert_success verify "'.data.mongodb-root-password'" matches "'^$root_password\$'" \
		for secret named "'${DEPLOYMENT_NAME}-mongodb'"

	local \
		mongo_uri="$(printf "mongodb://rocketchat:rocketchat@%s-mongodb-headless:27017/rocketchat?replicaSet=rs0" "$DEPLOYMENT_NAME" | base64)" \
		mongo_oplog_uri="$(printf "mongodb://root:root@%s-mongodb-headless:27017/local?replicaSet=rs0&authSource=admin" "$DEPLOYMENT_NAME" | base64)"
	run_and_assert_success verify "'.data.mongo-uri'" matches "'^$mongo_uri\$'" \
		for secret named "'${DEPLOYMENT_NAME}-rocketchat'"
	run_and_assert_success verify "'.data.mongo-oplog-uri'" matches "'^$mongo_oplog_uri\$'" \
		for secret named "'${DEPLOYMENT_NAME}-rocketchat'"
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
