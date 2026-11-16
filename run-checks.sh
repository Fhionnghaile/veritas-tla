#!/usr/bin/env bash
# Self-asserting formal-verification harness for the Veritas revocation model.
#   - the CORRECT verifier: TLC must find NO invariant violation (the proof);
#   - each guard removed: TLC must produce a counterexample (the guard is necessary).
# Exits non-zero unless all three outcomes are exactly as expected.
set -uo pipefail
cd "$(dirname "$0")"
JAR="${TLA_JAR:-tla2tools.jar}"
if [ ! -f "$JAR" ]; then
  echo "fetching tla2tools.jar ..."
  curl -sSL -o "$JAR" "https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar" \
    || { echo "could not download tla2tools.jar; set TLA_JAR to a local copy"; exit 2; }
fi
run(){ rm -rf "states_$1"; java -cp "$JAR" tlc2.TLC -metadir "states_$1" -config "$1.cfg" VeritasRevocation.tla 2>&1; }

fails=0
echo "== [1/3] correct verifier: expect NO violation =="
out=$(run correct)
if echo "$out" | grep -q "No error has been found"; then
  echo "  PASS — invariant holds across $(echo "$out" | grep -oE '[0-9]+ distinct states' | head -1)"
else echo "  FAIL — expected the invariant to hold"; echo "$out" | tail -5; fails=$((fails+1)); fi

for cfg in no_revocation no_expiry; do
  echo "== check: $cfg verifier: expect a counterexample =="
  out=$(run "$cfg")
  if echo "$out" | grep -q "Invariant SafeAccept is violated"; then
    echo "  PASS — TLC produced a counterexample (guard is necessary):"
    echo "$out" | grep -E "^State [0-9]+: <(Issue|Revoke|Tick|Verify)" | sed 's/^/     /'
  else echo "  FAIL — expected a counterexample"; echo "$out" | tail -5; fails=$((fails+1)); fi
done

echo
[ "$fails" -eq 0 ] && { echo "ALL CHECKS PASS (proof holds; both guards shown necessary)"; exit 0; } \
                   || { echo "CHECKS FAILED ($fails)"; exit 1; }
