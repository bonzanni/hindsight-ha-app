#!/usr/bin/env bash
# Task 9 harness: build the add-on, boot it + a local HA-ingress mimic, and run
# the Playwright ingress spec against the mounted-under-a-prefix control-plane.
#
# Why the mimic runs in the add-on's network namespace: the add-on's nginx only
# accepts the HA Supervisor IP and 127.0.0.1. `--network container:hs-smoke`
# lets the mimic reach the add-on on 127.0.0.1:8099 (allow-listed) while still
# publishing :8100 to the host (via hs-smoke's port map) for Playwright.
#
# Playwright runs inside the official image (browsers + system libs preinstalled)
# on the host network, so no browser deps need installing on the host.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${OPENROUTER_KEY:?Set OPENROUTER_KEY (e.g. from 1Password) to boot the add-on}"
IMG=hindsight-addon:dev
DATA="$(pwd)/.devdata"
PW_VERSION="$(node -e "console.log(require('@playwright/test/package.json').version)" 2>/dev/null || echo 1.60.0)"

cleanup() { docker rm -f hs-smoke ingress-mimic >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "== build =="
docker build -t "$IMG" hindsight/ >/dev/null

echo "== boot add-on =="
mkdir -p "$DATA"
docker run -d --name hs-smoke -p 8888:8888 -p 8099:8099 -p 8100:8100 \
  -e HINDSIGHT_API_LLM_API_KEY="$OPENROUTER_KEY" \
  -v "$DATA:/data" "$IMG" >/dev/null

echo -n "   waiting for API /health"
for i in $(seq 1 90); do
  curl -fsS http://localhost:8888/health >/dev/null 2>&1 && { echo " OK (${i}s)"; break; }
  [ "$i" = 90 ] && { echo " FAIL"; docker logs hs-smoke; exit 1; }
  sleep 1
done

echo -n "   waiting for control-plane via ingress"
for i in $(seq 1 60); do
  c=$(docker exec hs-smoke curl -s -o /dev/null -w '%{http_code}' \
    -H 'X-Ingress-Path: /test' http://127.0.0.1:8099/ 2>/dev/null)
  case "$c" in 2??|3??) echo " OK (${i}s, HTTP $c)"; break ;; esac
  [ "$i" = 60 ] && { echo " FAIL (last HTTP $c)"; docker logs hs-smoke; exit 1; }
  sleep 1
done

echo "== seed a 'Test' memory bank (for the bank-navigation regression test) =="
docker exec hs-smoke sh -c 'printf "%s" "{\"name\":\"Test\"}" | curl -s -o /dev/null -w "PUT bank Test: HTTP %{http_code}\n" -X PUT -H "Content-Type: application/json" --data @- http://127.0.0.1:8888/v1/default/banks/Test'

echo "== start ingress mimic (in add-on netns) =="
docker run -d --name ingress-mimic --network container:hs-smoke \
  -v "$PWD/tests/ingress-mimic.conf:/etc/nginx/nginx.conf:ro" nginx:stable >/dev/null
sleep 1

echo "== run Playwright (official v${PW_VERSION} image, host network) =="
docker run --rm --network host -v "$PWD":/work -w /work -e HOME=/work \
  "mcr.microsoft.com/playwright:v${PW_VERSION}-noble" \
  npx playwright test "$@"
echo "INGRESS TEST PASS"
