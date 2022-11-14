#!/bin/bash

load "../common.bash"

bats_require_minimum_version 1.5.0

# To test
# OVERWRITE_SETTING
# Setting_id
# Upgrade from last known version
# all supported parameters from .env (docker compose config)

# tries to find the last stable release we had in order to try an upgrade test
find_last_stable_version() {
	#shellcheck disable=2206
	local current_version_arr=(${ROCKETCHAT_TAG//./ })
	local last_stable=
	for i in $(seq 2 0); do
		local version_component="${current_version_arr[$i]}"
		while ((version_component > 0)); do
			version_component=$((version_component - 1))
			local attempt=
			for j in $(seq 0 2); do
				if ((j == i)); then
					attempt+=".$version_component"
					continue
				fi
				attempt+=".${current_version_arr[$j]}"
			done
			attempt="${attempt%.}"
			if curl "https://releases.rocket.chat/$attempt/info" --silent | jq -e '.tag' >/dev/null; then
				last_stable="$attempt"
				break
			fi
		done
		[[ -n "$last_stable" ]] && break
	done
	echo "$last_stable"
}

@test "Should be a valid compose template" {
	docker compose config -q
}

# OOTB one-"click" experience
@test "Should generate expected deployment config with an empty .env" {
	local project_name=
	project_name="$(basename "$(pwd)")"
	project_name="${project_name//./}"
	run --separate-stderr docker compose config --format json
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
	assert_field_equal services mongodb image "docker.io/bitnami/mongodb:4.4" # TODO: add assert_field_equal_regex to verify image tags
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
		[RELEASE]=0.0.1
	)
	for variable in "${!variables[@]}"; do
		printf "%s=%s\n" "$variable" "${variables[$variable]}" >>.env
	done
	run --separate-stderr docker compose config --format json
	assert_success
	assert_field_equal services mongodb environment MONGODB_INITIAL_PRIMARY_PORT_NUMBER "27018"
	assert_field_equal services mongodb environment MONGODB_PORT_NUMBER "27018"
	assert_field_equal services mongodb environment MONGODB_REPLICA_SET_NAME "rocket_rs0"
	assert_field_equal services rocketchat environment MONGO_URL "mongodb://mongodb:27018/rocketchat?replicaSet=rocket_rs0"
	assert_field_equal services rocketchat environment MONGO_OPLOG_URL "mongodb://mongodb:27018/local?replicaSet=rocket_rs0"
	assert_field_equal services rocketchat environment PORT "3001"
	assert_field_equal services rocketchat environment ROOT_URL "http://localhost:80"
	assert_field_equal services rocketchat image "registry.rocket.chat/rocketchat/rocket.chat:0.0.1"
	assert_field_equal services rocketchat expose 0 "3001"
	assert_field_equal services rocketchat ports 0 host_ip '127.0.0.1'
	assert_field_equal services rocketchat ports 0 target "3001"
	assert_field_equal services rocketchat ports 0 published "80"
	echo "# Removing temporary .env file" >&3
	rm -f .env
}

@test "Server should start up successfully with default config" {
	run docker compose up -d
	assert_success
	ROCKETCHAT_MAX_ATTEMPTS=200 wait_for_server
}
