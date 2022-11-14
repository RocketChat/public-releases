#!/bin/bash

source _.bash

sudo apt install jq jo -y

bats pre ./snap/tests.bats
bats 'pre,post' ./api_basic/api.bats
bats post ./snap/tests.bats
