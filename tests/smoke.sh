#!/usr/bin/env bash
# Smoke test: build the add-on image, boot it standalone, assert API health
# and that pg0 data persists across a container restart.
set -euo pipefail

: "${OPENROUTER_KEY:?Set OPENROUTER_KEY to run the smoke test}"
IMG=hindsight-addon:dev
DATA="$(pwd)/.devdata"
rm -rf "$DATA"; mkdir -p "$DATA"

echo "== build =="
docker build -t "$IMG" hindsight/

run() {
  docker run -d --name hs-smoke \
    -p 8888:8888 -p 8099:8099 \
    -e HINDSIGHT_API_LLM_API_KEY="$OPENROUTER_KEY" \
    -v "$DATA:/data" "$IMG"
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

docker rm -f hs-smoke
echo "SMOKE PASS"
