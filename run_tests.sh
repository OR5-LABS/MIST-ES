#!/usr/bin/env bash
# run_tests.sh -- run every MIST-ES test target and compare its exit code and
# PASS/FAIL verdict-line counts with the recorded baseline in tests/expected.txt.
# Most testbenches end with $finish, so exit codes alone cannot be trusted;
# counting verdict lines also catches silent failures and silently removed tests.
#
#   ./run_tests.sh             check against tests/expected.txt (CI mode)
#   ./run_tests.sh --baseline  re-record tests/expected.txt from this run
#
# A target is "<script>[:<argument>]", e.g. build.sh:pmp runs `bash build.sh pmp`.
# A line in tests/expected.txt may end with "# KNOWN: <reason>" to mark a
# documented known failure; the recorded result must still match exactly.
set -u
cd "$(dirname "$0")"
mkdir -p build/test-logs
mode="${1:-check}"

TARGETS="build.sh:sim build.sh:cosim build.sh:rvfi build.sh:debug
         build.sh:pmp build.sh:epmp build.sh:upriv build.sh:mml
         build.sh:ecc build.sh:axil build.sh:fpga
         run_isa.sh:all coremark/run_coremark_10.sh dhrystone/run_dhrystone.sh"

count() {  # $1 = log -> "pass fail"
  local p f
  p=$(grep -aE '\bPASS(ED)?\b' "$1" | wc -l)
  # "FAIL=0x..." is build_smoke.py printing its FAIL label address, not a verdict
  f=$(grep -aE '\bFAIL(ED|URE)?\b' "$1" | grep -avE 'FAIL=0x' | wc -l)
  echo "$p $f"
}

run_target() {  # $1 = target, $2 = log; returns the script's exit code
  local script="${1%%:*}" arg=""
  [[ "$1" == *:* ]] && arg="${1#*:}"
  timeout 3600 bash "$script" $arg > "$2" 2>&1
}

logname() { echo "build/test-logs/$(echo "$1" | tr '/:' '__').log"; }

if [ "$mode" = "--baseline" ]; then
  : > tests/expected.txt.new
  for t in $TARGETS; do
    log=$(logname "$t")
    run_target "$t" "$log"; rc=$?
    read -r p f < <(count "$log")
    known=$(grep -E "^$t " tests/expected.txt 2>/dev/null | sed -n 's/.*# KNOWN: //p')
    printf '%s %s %s %s%s\n' "$t" "$rc" "$p" "$f" "${known:+ # KNOWN: $known}" | tee -a tests/expected.txt.new
  done
  mv tests/expected.txt.new tests/expected.txt
  exit 0
fi

status=0
while read -r t erc ep ef rest; do
  case "$t" in ''|\#*) continue ;; esac
  log=$(logname "$t")
  run_target "$t" "$log"; rc=$?
  read -r p f < <(count "$log")
  known=$(echo "$rest" | sed -n 's/.*# KNOWN: //p')
  if [ "$rc" = "$erc" ] && [ "$p" = "$ep" ] && [ "$f" = "$ef" ]; then
    if [ -n "$known" ]; then echo "KNOWN   $t  ($known)"; else echo "PASS    $t"; fi
  else
    echo "FAIL    $t  exit=$rc (expected $erc)  PASS lines=$p (expected $ep)  FAIL lines=$f (expected $ef)  log: $log"
    status=1
  fi
done < tests/expected.txt
exit $status
