#!/bin/bash

load "../common.bash"

bats_require_minimum_version 1.5.0

# To test
# OVERWRITE_SETTING
# Setting_id
# Upgrade from last known version
# all supported parameters from .env (docker compose config)

find_last_version() {
	local version=
	if [[ $ROCKETCHAT_TAG =~ ^([0-9]+\.[0-9]+\.[0-9]+)-rc\.[0-9]+$ ]]; then
		version=${BASH_REMATCH[1]}
	else
		version=$ROCKETCHAT_TAG
	fi
	local current=(${version//./ })
	local major="${current[0]}"
	local minor="${current[1]}"
	local patch=$((${current[2]} - 1))
	while ((major >= (major - 1))); do
		while ((minor >= 0)); do
			while ((patch >= 0)); do
				_v="${major}.${minor}.${patch}"
				if [[ -n "$(curl -s https://releases.rocket.chat/$_v/info | jq -r '.tag // empty')" ]]; then
					printf "%s" "$_v"
					return
				fi
				patch=$((patch - 1))
			done
			patch=9
			minor=$((minor - 1))
		done
		minor=9
		major=$((major - 1))
	done
}

setup_file() {
	export ROCKETCHAT_LAST_TAG="$(find_last_version)"
	echo "last version: $ROCKETCHAT_LAST_TAG" >&3
	echo "current version: $ROCKETCHAT_TAG" >&3
}

@test "Should be a valid compose template" {
	docker compose -f "$COMPOSE_FILE" config -q
}

# OOTB one-"click" experience
@test "Should generate expected deployment config with an empty .env" {
	local project_name=
	project_name="$(basename "$(pwd)")"
	project_name="${project_name//./}"
	project_name="${project_name,,}"
	run --separate-stderr docker compose -f "$COMPOSE_FILE" config --format json
	assert_success
	# name
	assert_field_equal name "$project_name"

	# envronment variables
	# mongodb
	assert_field_equal services mongodb environment ALLOW_EMPTY_PASSWORD "yes"
	assert_field_equal services mongodb environment MONGODB_ADVERTISED_HOSTNAME "mongodb"
	assert_field_equal services mongodb environment MONGODB_ENABLE_JOURNAL "true"
	assert_field_equal services mongodb environment MONGODB_INITIAL_PRIMARY_HOST "mongodb"
	assert_field_equal services mongodb environment MONGODB_INITIAL_PRIMARY_PORT_NUMBER "27017"
	assert_field_equal services mongodb environment MONGODB_PORT_NUMBER "27017"
	assert_field_equal services mongodb environment MONGODB_REPLICA_SET_MODE "primary"
	assert_field_equal services mongodb environment MONGODB_REPLICA_SET_NAME "rs0"
	# rocketchat
	assert_field_equal services rocketchat environment MONGO_URL "mongodb://mongodb:27017/rocketchat?replicaSet=rs0"
	assert_field_equal services rocketchat environment MONGO_OPLOG_URL "mongodb://mongodb:27017/local?replicaSet=rs0"
	assert_field_equal services rocketchat environment DEPLOY_METHOD "docker"
	assert_field_equal services rocketchat environment DEPLOY_PLATFORM ""
	assert_field_equal services rocketchat environment PORT "3000"
	assert_field_equal services rocketchat environment ROOT_URL "http://localhost:3000"

	# images
	assert_field_equal services mongodb image "docker.io/bitnami/mongodb:5.0" # TODO: add assert_field_equal_regex to verify image tags
	assert_field_equal services rocketchat image "registry.rocket.chat/rocketchat/rocket.chat:latest"

	# networks
	assert_field_equal networks default name "${project_name}_default"
	assert_field_equal networks default ipam "{}"
	assert_field_equal networks default external "false"
	# services
	assert_field_equal services mongodb networks default "null"
	assert_field_equal services rocketchat networks default "null"

	# volumes
	assert_field_equal volumes mongodb_data name "${project_name}_mongodb_data"
	assert_field_equal volumes mongodb_data driver "local"
	assert_field_equal volumes mongodb_data external "false"
	# service::mongodb
	assert_field_equal services mongodb volumes 0 type "volume"
	assert_field_equal services mongodb volumes 0 source "mongodb_data"
	assert_field_equal services mongodb volumes 0 target "/bitnami/mongodb"

	# restart policies
	assert_field_equal services mongodb restart 'on-failure'
	assert_field_equal services rocketchat restart 'on-failure'

	# rest of rocketchat config
	assert_field_equal services rocketchat depends_on mongodb condition "service_started"
	assert_field_equal services rocketchat expose 0 "3000"
	#labels
	assert_field_equal services rocketchat labels "traefik.enable" "true"
	assert_field_equal services rocketchat labels "traefik.http.routers.rocketchat.entrypoints" "https"
	assert_field_equal services rocketchat labels "traefik.http.routers.rocketchat.rule" 'Host(``)'
	assert_field_equal services rocketchat labels "traefik.http.routers.rocketchat.tls" "true"
	assert_field_equal services rocketchat labels "traefik.http.routers.rocketchat.tls.certresolver" "le"
	#ports
	assert_field_equal services rocketchat ports 0 mode "ingress"
	assert_field_equal services rocketchat ports 0 host_ip '0.0.0.0'
	assert_field_equal services rocketchat ports 0 target "3000"
	assert_field_equal services rocketchat ports 0 published "3000"
	assert_field_equal services rocketchat ports 0 protocol "tcp"
}

@test "Should generate right config after modifying environment variables" {
	declare -A variables=(
		[PORT]=3001
		[BIND_IP]="127.0.0.1"
		[HOST_PORT]=80
		[MONGODB_REPLICA_SET_NAME]=rocket_rs0
		[MONGODB_PORT_NUMBER]=27018
		[MONGODB_INITIAL_PRIMARY_PORT_NUMBER]=27018
		[RELEASE]=$ROCKETCHAT_LAST_TAG
	)
	for variable in "${!variables[@]}"; do
		printf "%s=%s\n" "$variable" "${variables[$variable]}" >>.env
	done
	run --separate-stderr docker compose -f "$COMPOSE_FILE" config --format json
	assert_success
	assert_field_equal services mongodb environment MONGODB_INITIAL_PRIMARY_PORT_NUMBER "27018"
	assert_field_equal services mongodb environment MONGODB_PORT_NUMBER "27018"
	assert_field_equal services mongodb environment MONGODB_REPLICA_SET_NAME "rocket_rs0"
	assert_field_equal services rocketchat environment MONGO_URL "mongodb://mongodb:27018/rocketchat?replicaSet=rocket_rs0"
	assert_field_equal services rocketchat environment MONGO_OPLOG_URL "mongodb://mongodb:27018/local?replicaSet=rocket_rs0"
	assert_field_equal services rocketchat environment PORT "3001"
	assert_field_equal services rocketchat environment ROOT_URL "http://localhost:80"
	assert_field_equal services rocketchat image "registry.rocket.chat/rocketchat/rocket.chat:$ROCKETCHAT_LAST_TAG"
	assert_field_equal services rocketchat expose 0 "3001"
	assert_field_equal services rocketchat ports 0 host_ip '127.0.0.1'
	assert_field_equal services rocketchat ports 0 target "3001"
	assert_field_equal services rocketchat ports 0 published "80"
	echo "# Removing temporary .env file" >&3
	rm -f .env
}

@test "Server should start up (last version) successfully with default config" {
	printf "%s=%s\n" "RELEASE" "$ROCKETCHAT_LAST_TAG" >>.env
	run docker compose -f "$COMPOSE_FILE" up -d
	assert_success
	ROCKETCHAT_MAX_ATTEMPTS=200 wait_for_server
	echo "# Removing temporary .env file" >&3
	rm -f .env
}

@test "Should upgrade to newer version as expected" {
	printf "%s=%s\n" "RELEASE" "$ROCKETCHAT_TAG" >>.env
	run_and_assert_success docker compose -f "$COMPOSE_FILE" up -d
	ROCKETCHAT_MAX_ATTEMPTS=200 wait_for_server
	# don't remove .env
}

@test "Should start fine with OVERWRITE_SETTING on an existing setting" {
	printf "OVERWRITE_SETTING_Site_Url=http://127.0.0.1\n" >>.env
	run_and_assert_success docker compose -f "$COMPOSE_FILE" up -d --force-recreate
	ROCKETCHAT_MAX_ATTEMPTS=200 wait_for_server
}

teardown_file() {
	rm -f .env
}
