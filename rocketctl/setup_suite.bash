#!/bin/bash
load "../common.bash"

setup_suite() {
	if [[ -d './install.sh' ]]; then
		echo "# skipping clone" >&3
		return
	fi

	echo "# cloning rocketchatctl script repository" >&3
	ROCKETCHATCTL_REPOSITORY_WORKING_BRANCH="${ROCKETCHATCTL_REPOSITORY_WORKING_BRANCH:-main}"
	git clone --branch "$ROCKETCHATCTL_REPOSITORY_WORKING_BRANCH" --recursive https://github.com/RocketChat/install.sh >&3 ||
		fail "failed to clone main repository"
	echo "# cloned successfully" >&3
}
