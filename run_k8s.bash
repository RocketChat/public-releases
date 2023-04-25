#!/bin/bash

set -Eeuo pipefail

source _.bash

bats k8s/lint.bats

export ROCKETCHAT_HOST="bats.rocket.chat"
for type in monolith microservices; do
	bats pre k8s/$type.bats
	declare -g ip=
	if ! ip="$(
		\kubectl -n kube-system get svc traefik \
			--output "jsonpath={.status.loadBalancer.ingress[0].ip}"
	)" || [[ -z "$ip" ]]; then
		\echo "[ERROR] load balancer IP not found"
		exit 1
	fi
	export ROCKETCHAT_URL="http://$ip"
	bats 'pre,post' ./api_basic/api.bats
	bats post k8s/$type.bats
done

