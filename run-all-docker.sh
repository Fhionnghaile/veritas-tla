#!/usr/bin/env bash
# Runs everything in throwaway Docker containers (Windows Git Bash or Linux/macOS):
# TLC model checks + trace validation of the real Veritas verifier. Writes results/.
set -u
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")" && pwd)"
VERITAS="${VERITAS_DIR:-$HERE/../../../Phase 1 - Already Built/Veritas/veritas}"
win(){ command -v cygpath >/dev/null && cygpath -w "$1" || echo "$1"; }
[ -d "$VERITAS/src" ] || { echo "Veritas source not found at $VERITAS (set VERITAS_DIR)"; exit 2; }
if [ ! -f "$HERE/tla2tools.jar" ]; then
  echo "fetching tla2tools.jar ..."
  docker run --rm -v "$(win "$HERE"):/w" python:3.12 python -c \
    "import urllib.request;urllib.request.urlretrieve('https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar','/w/tla2tools.jar')" || exit 2
fi
docker run --rm -v "$(win "$HERE"):/w" -w /w eclipse-temurin:21 bash run-checks.sh; tlc=$?
echo "== [8] trace validation: model vs the real Veritas PHP verifier =="
tv=0
for d in states_correct states_correct_3x5; do
  f="$d.dump"; [ -f "$HERE/$f" ] || f="$d.dump.dump"
  docker run --rm -v "$(win "$HERE"):/w" -v "$(win "$VERITAS"):/veritas:ro" -w /w php:8.3-cli \
    php trace/validate.php "$f" /veritas/src | tee "$HERE/results/trace_${d#states_}.txt" | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || tv=1
done
echo; [ $tlc -eq 0 ] && [ $tv -eq 0 ] && echo "EVERYTHING PASSES (model checks + trace validation)" || echo "SOMETHING FAILED (model checks exit $tlc, trace validation $tv)"
