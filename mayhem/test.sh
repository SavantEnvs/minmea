#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TB="$SRC/build/test"
[ -x "$TB/tests" ] && [ -x "$TB/example" ] || { echo "missing $TB/{tests,example}: build.sh must produce them" >&2; exit 1; }

passed=0 failed=0

# 1) Upstream's libcheck suite; parse its own summary line ("100%: Checks: N, Failures: F, Errors: E").
out="$("$TB/tests" 2>&1)" || true
echo "$out"
if sum="$(printf '%s\n' "$out" | grep -E '^[0-9]+%: Checks: [0-9]+, Failures: [0-9]+, Errors: [0-9]+')"; then
  checks="$(printf '%s' "$sum" | sed -E 's/.*Checks: ([0-9]+),.*/\1/')"
  fails="$(printf '%s' "$sum" | sed -E 's/.*Failures: ([0-9]+),.*/\1/')"
  errs="$(printf '%s' "$sum" | sed -E 's/.*Errors: ([0-9]+).*/\1/')"
  bad=$(( fails + errs ))
  if [ "$checks" -ge 30 ]; then passed=$(( passed + checks - bad )); failed=$(( failed + bad ))
  else echo "suspiciously few libcheck tests ($checks)" >&2; failed=$(( failed + 1 )); fi
else
  echo "no libcheck summary line in output" >&2; failed=$(( failed + 1 ))
fi

# 2) Known-answer probes through example.c: fixed NMEA sentence in, exact parsed values out.
kat() {  # kat <name> <input> <expected-substring>
  local got
  got="$(printf '%s\n' "$2" | "$TB/example" 2>&1 || true)"
  if printf '%s' "$got" | grep -qF -- "$3"; then passed=$(( passed + 1 )); echo "KAT ok: $1"
  else failed=$(( failed + 1 )); echo "KAT FAIL: $1: expected '$3' in:" >&2; echo "$got" >&2; fi
}
kat rmc-raw '$GPRMC,123205.00,A,5106.94085,N,01701.51689,E,0.016,,280214,,,A*7B' '(510694085/100000,170151689/100000) 16/1000'
kat rmc-rescale '$GPRMC,123205.00,A,5106.94085,N,01701.51689,E,0.016,,280214,,,A*7B' 'scaled to three decimal places: (5106941,1701517) 16'
kat gga-fix '$GPGGA,123204.00,5106.94086,N,01701.51680,E,1,06,3.86,127.9,M,40.5,M,,*51' 'fix quality: 1'
kat zda '$GPZDA,160012.71,11,03,2004,-1,00*7D' '$xxZDA: 16:0:12 11.03.2004 UTC-01:00'
kat bad-checksum '$GPTXT,01,01,02,ANTSTATUS=INIT*26' 'sentence is not valid'

emit_ctrf "minmea-check" "$passed" "$failed" 0
