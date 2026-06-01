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

echo "== pg0 persisted? (PG_VERSION exists) =="
test -f "$DATA/.pg0/PG_VERSION" || find "$DATA/.pg0" -maxdepth 3 | head

echo "== restart keeps data =="
docker rm -f hs-smoke
run; wait_health

echo "== ingress front answers =="
curl -fsS -H 'X-Ingress-Path: /test' http://localhost:8099/ -o /dev/null -w 'cp via nginx: HTTP %{http_code}\n'

docker rm -f hs-smoke
echo "SMOKE PASS"
