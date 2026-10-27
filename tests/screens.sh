#!/usr/bin/env bash
# screens.sh NAME... -- runs the screen tests tests/NAME.sh, E2E_JOBS at
# once, half the host's CPUs unless set, and writes each one's output
# whole, in the order named, once all are done. Each boots its own QEMU,
# with its own sockets, dumps and disks in build/, and spends most of its
# time waiting for the board, so several at once take little longer
# than the longest. Exits 1 if any failed, naming them. Run from the top
# of the project, after what make e2e builds first.
set -u
cd "$(dirname "$0")/.."
BUILD=build
mkdir -p "$BUILD/screens"
at_once=${E2E_JOBS:-$(( $(getconf _NPROCESSORS_ONLN) / 2 ))}
[ "$at_once" -ge 1 ] || at_once=1
for name in "$@"; do
  while [ "$(jobs -rp | wc -l)" -ge "$at_once" ]; do sleep 0.2; done
  { tests/"$name".sh; echo $? > "$BUILD/screens/$name.status"; } > "$BUILD/screens/$name.log" 2>&1 &
done
wait
failed=()
for name in "$@"; do
  cat "$BUILD/screens/$name.log"
  [ "$(cat "$BUILD/screens/$name.status" 2> /dev/null)" = 0 ] || failed+=("$name")
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "# screen tests failed: ${failed[*]}"
  exit 1
fi
echo "# screen tests: all $# passed"
