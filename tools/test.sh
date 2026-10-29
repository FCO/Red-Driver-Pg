#!/bin/sh
set -eu

driver_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
red_source=${RED_SOURCE:-/red}
export RED_SOURCE="$red_source"

cd "$driver_root"
prove6 -j "${TEST_JOBS:-4}" -e "bash $driver_root/tools/pg-test-exec.sh" t

cd "$red_source"
prove6 -j "${TEST_JOBS:-4}" -e "bash $driver_root/tools/pg-test-exec.sh" t
