#!/bin/bash

source _.bash

bats pre ./snap/snap.bats
bats 'pre,post' ./api_basic/api.bats
bats post ./snap/snap.bats
