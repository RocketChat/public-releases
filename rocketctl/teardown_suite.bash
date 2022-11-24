#!/bin/bash

teardown_suite() {
	echo "# cleaning up rocketctl" >&3
	rm -rvf install.sh
}
