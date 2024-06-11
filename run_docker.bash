#!/bin/bash

set -Eeuo pipefail

source _.bash

set -x

bats docker/compose.bats
