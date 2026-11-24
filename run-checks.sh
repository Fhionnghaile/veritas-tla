#!/usr/bin/env bash
# Self-asserting formal-verification harness for the Veritas revocation models.
#   Model checking (TLC):
#     - correct verifier, two bounds: NO invariant violation (the proof);
#     - each guard removed: a counterexample (each guard is necessary);
#     - cached revocation list: bounded staleness HOLDS with the freshness guard,
#       FAILS without it, and strict revocation is shown impossible offline.
#   Trace validation (needs php with sodium + the Veritas source):
#     - TLC dumps every reachable state of the correct model; trace/validate.php replays
#       each one against the REAL Veritas PHP verifier and fails on any disagreement.
# Full TLC transcripts are written to results/. Exits non-zero unless every outcome is as expected.
set -uo pipefail
cd "$(dirname "$0")"
JAR="${TLA_JAR:-tla2tools.jar}"
VERITAS_SRC="${VERITAS_SRC:-../veritas/src}"
if [ ! -f "$JAR" ]; then
  echo "fetching tla2tools.jar ..."
  curl -sSL -o "$JAR" "https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar" \
    || { echo "could not download tla2tools.jar; set TLA_JAR to a local copy"; exit 2; }
fi
mkdir -p results
tlc(){ # spec cfg [extra TLC args...]
  local spec="$1" cfg="$2"; shift 2
  rm -rf "states_$cfg"
  java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -metadir "states_$cfg" -config "$cfg.cfg" "$@" "$spec.tla" 2>&1 | tee "results/$cfg.txt"
}
fails=0
expect_pass(){ # spec cfg label
  echo "== $3: expect NO violation =="
  out=$(tlc "$1" "$2" ${4:+$4})
  if echo "$out" | grep -q "No error has been found"; then
    echo "  PASS — holds across $(echo "$out" | grep -oE '[0-9]+ distinct states' | head -1)"
  else echo "  FAIL — expected the invariant to hold"; echo "$out" | tail -5; fails=$((fails+1)); fi
}
expect_cex(){ # spec cfg label
  echo "== $3: expect a counterexample =="
  out=$(tlc "$1" "$2")
  if echo "$out" | grep -qE "Invariant [A-Za-z]+ is violated"; then
    echo "  PASS — TLC produced the counterexample:"
    echo "$out" | grep -E "^State [0-9]+: <(Issue|Revoke|Refresh|Tick|Verify)" | sed -E 's/ line [0-9].*//; s/^/     /'
  else echo "  FAIL — expected a counterexample"; echo "$out" | tail -5; fails=$((fails+1)); fi
}

expect_pass VeritasRevocation correct      "[1] correct verifier (2 credentials, horizon 3)" "-dump states_correct.dump"
expect_pass VeritasRevocation correct_3x5  "[2] correct verifier (3 credentials, horizon 5)" "-dump states_correct_3x5.dump"
expect_cex  VeritasRevocation no_revocation "[3] revocation check removed"
expect_cex  VeritasRevocation no_expiry     "[4] expiry check removed"
expect_pass VeritasRevocationCache cache_bounded   "[5] cached list + freshness guard: bounded staleness"
expect_cex  VeritasRevocationCache cache_unbounded "[6] cached list, NO freshness guard: stale acceptance"
expect_cex  VeritasRevocationCache cache_strict    "[7] cached list: strict revocation is impossible offline"

echo "== [8] trace validation: model vs the real Veritas PHP verifier =="
if command -v php >/dev/null && [ -d "$VERITAS_SRC" ]; then
  for d in states_correct states_correct_3x5; do
    f="$d.dump"; [ -f "$f" ] || f="$d.dump.dump"
    php trace/validate.php "$f" "$VERITAS_SRC" | tee "results/trace_${d#states_}.txt" | sed 's/^/  /' || fails=$((fails+1))
  done
elif [ "${REQUIRE_TRACE:-0}" = 1 ]; then echo "  FAIL — php or $VERITAS_SRC missing"; fails=$((fails+1))
else echo "  SKIPPED here (needs php + the Veritas source at \$VERITAS_SRC); CI runs it"; fi

echo
[ "$fails" -eq 0 ] && { echo "ALL CHECKS PASS"; exit 0; } || { echo "CHECKS FAILED ($fails)"; exit 1; }
