#!/usr/bin/env bash
# Smoke test: build the add-on image, boot it standalone, assert API health
# and that pg0 data persists across a container restart.
set -euo pipefail

TESTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/lib/test-image.sh
source "$TESTS_DIR/lib/test-image.sh"

: "${OPENROUTER_KEY:?Set OPENROUTER_KEY to run the smoke test}"
IMG=$(test_image_ref)
DATA="$(pwd)/.devdata"
rm -rf "$DATA"; mkdir -p "$DATA"

prepare_test_image hindsight/

run() {
  # Extra docker args (e.g. -e overrides) may be passed through.
  docker run -d --name hs-smoke \
    -p 8888:8888 -p 8099:8099 \
    -e HINDSIGHT_API_LLM_API_KEY="$OPENROUTER_KEY" \
    -v "$DATA:/data" "$@" "$IMG"
}

wait_health() {
  for i in $(seq 1 90); do
    if curl -fsS http://localhost:8888/health >/dev/null 2>&1; then
      echo "health OK after ${i}s"; return 0
    fi
    sleep 1
  done
  echo "FAIL: /health never came up"; docker logs hs-smoke; return 1
}

echo "== first boot =="
docker rm -f hs-smoke 2>/dev/null || true
run; wait_health

echo "== pg0 persisted? (cluster PG_VERSION exists on the /data volume) =="
# pg0 lays its cluster down under instances/<name>/data (name=hindsight).
PGV="$DATA/.pg0/instances/hindsight/data/PG_VERSION"
test -f "$PGV" || { echo "FAIL: no pg0 cluster at $PGV"; find "$DATA/.pg0" -maxdepth 3 | head; exit 1; }
echo "pg0 cluster present: $(cat "$PGV" | tr -d '\n') (PG_VERSION)"

echo "== restart keeps data =="
docker rm -f hs-smoke
run; wait_health

echo "== ingress front answers (from an ingress-allowed source) =="
# HA ingress connects from the Supervisor (172.30.32.2); a host -p 8099 curl
# arrives via Docker source-NAT and trips the nginx deny-all (returns 403).
# Verify from inside the container instead — 127.0.0.1 is allow-listed — which
# also exercises the full nginx -> control-plane proxy path.
#
# The Next.js control-plane (:9999) boots a few seconds AFTER the API /health
# is green, so poll the ingress root until the CP upstream stops 502-ing.
wait_cp() {
  for i in $(seq 1 60); do
    c=$(docker exec hs-smoke curl -s -o /dev/null -w '%{http_code}' \
      -H 'X-Ingress-Path: /test' http://127.0.0.1:8099/ 2>/dev/null)
    case "$c" in 2??|3??) echo "$c"; return 0 ;; esac
    sleep 1
  done
  echo "$c"; return 1
}
code=$(wait_cp)
echo "cp via nginx (internal): HTTP $code"
case "$code" in
  2??|3??) : ;;  # 200 or the CP's redirect (307) both prove nginx proxied to the CP
  *) echo "FAIL: ingress front returned $code"; docker logs hs-smoke | tail -40; exit 1 ;;
esac
# And confirm the API is reachable through the ingress port (api locations).
hcode=$(docker exec hs-smoke curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8099/health)
echo "api /health via nginx (internal): HTTP $hcode"
[ "$hcode" = "200" ] || { echo "FAIL: /health via nginx = $hcode"; docker logs hs-smoke | tail -40; exit 1; }

echo "== recall handler deadline (patched-in) returns 504 fast =="
# Rebooted with a 1ms deadline: any real recall must trip it deterministically
# (query embedding alone takes ~20ms). Proves the deadline patch is live.
docker rm -f hs-smoke
run -e HINDSIGHT_API_RECALL_HANDLER_TIMEOUT=0.001; wait_health
dcode=$(docker exec hs-smoke curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
  -X POST http://127.0.0.1:8888/v1/default/banks/smoketest/memories/recall \
  -H 'Content-Type: application/json' \
  -d '{"query":"deadline probe","budget":"low","max_tokens":256}')
echo "recall with 1ms deadline: HTTP $dcode"
[ "$dcode" = "504" ] || { echo "FAIL: expected 504, got $dcode"; docker logs hs-smoke | tail -40; exit 1; }

echo "== clean SIGTERM stop (bounded worker drain; no exit 137) =="
t0=$(date +%s)
docker stop -t 60 hs-smoke >/dev/null
t1=$(date +%s)
ec=$(docker inspect -f '{{.State.ExitCode}}' hs-smoke)
echo "stop took $((t1-t0))s, container exit code $ec"
[ "$ec" = "0" ] || { echo "FAIL: exit code $ec (expected 0 — SIGKILL regression?)"; exit 1; }
[ $((t1-t0)) -le 30 ] || { echo "FAIL: stop took $((t1-t0))s (>30s)"; exit 1; }

docker rm -f hs-smoke
echo "SMOKE PASS"
