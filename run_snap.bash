#!/bin/bash

source _.bash

bats pre ./snap/tests.bats
bats 'pre,post' ./api_basic/api.bats
bats post ./snap/tests.bats
