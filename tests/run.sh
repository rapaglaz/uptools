#!/usr/bin/env bash
# Runs every test file and fails if any of them fails.
#
# usage: tests/run.sh

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0
for test_file in smoke modules; do
  bash "$dir/$test_file.sh" || status=1
done
exit "$status"
