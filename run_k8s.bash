#!/bin/bash

#set -Eeuo pipefail

source _.bash

bats k8s/lint.bats

declare -A ascii_arts=(
	[monolith]="
  __  __                           _   _   _     _     
 |  \/  |                         | | (_) | |   | |    
 | \  / |   ___    _ __     ___   | |  _  | |_  | |__  
 | |\/| |  / _ \  | '_ \   / _ \  | | | | | __| | '_ \ 
 | |  | | | (_) | | | | | | (_) | | | | | | |_  | | | |
 |_|  |_|  \___/  |_| |_|  \___/  |_| |_|  \__| |_| |_|

"
	[microservices]="
  __  __   _                                                     _                     
 |  \/  | (_)                                                   (_)                    
 | \  / |  _    ___   _ __    ___    ___    ___   _ __  __   __  _    ___    ___   ___ 
 | |\/| | | |  / __| | '__|  / _ \  / __|  / _ \ | '__| \ \ / / | |  / __|  / _ \ / __|
 | |  | | | | | (__  | |    | (_) | \__ \ |  __/ | |     \ V /  | | | (__  |  __/ \__ \
 |_|  |_| |_|  \___| |_|     \___/  |___/  \___| |_|      \_/   |_|  \___|  \___| |___/
                                                                                       
"
)

export ROCKETCHAT_HOST="bats.rocket.chat"
for type in monolith; do
	echo "${ascii_arts[$type]}"
	bats pre k8s/$type.bats
	bats post k8s/$type.bats
 	kubectl get secrets -A
done

