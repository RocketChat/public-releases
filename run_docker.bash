#!/bin/bash

set -Eeuo pipefail

source _.bash

bats docker/compose.bats
