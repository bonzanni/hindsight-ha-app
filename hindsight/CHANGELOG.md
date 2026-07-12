# Changelog

## 0.2.0

Recall latency + graceful shutdown, tuned for low-power (N150-class) hosts.
Measured on-device at 0.1.1: one recall reranked 300 candidates in ~6.3s idle
(96% of handler time); two concurrent recalls degraded superlinearly to ~25s
each (thread oversubscription), silently blowing consumers' 20s client budget
— the server kept working on requests whose callers had already disconnected.

- Rerank depth capped at 100 candidates (was 300) — the cross-encoder now
  scores the RRF top-100. ~3x less CPU per recall; final results still
  token-filtered the same way.
- Cross-encoder calls serialized (`RERANKER_LOCAL_MAX_CONCURRENT=1`) and
  upstream's quality-identical length-bucketed batching enabled; OpenMP idle
  spinning disabled (`OMP_WAIT_POLICY=PASSIVE`). Kills the superlinear
  collapse under concurrency.
- New recall handler deadline (patched into the pinned upstream API,
  `HINDSIGHT_API_RECALL_HANDLER_TIMEOUT=15`): a recall that cannot finish in
  15s returns 504 immediately instead of overrunning the caller's timeout
  invisibly. No more accepted-but-never-answered requests.
- Background consolidation limited to one worker slot so it can no longer
  gang up with interactive recalls on the 4 cores.
- Clean SIGTERM: worker drain is now bounded (8s, patched-in
  `HINDSIGHT_API_WORKER_SHUTDOWN_TIMEOUT`), `S6_KILL_GRACETIME` dropped from
  30s to 5s (s6 sat out the full 30s *after* services had already stopped
  cleanly — the container could never stop within the Supervisor's default
  10s grace, so every nightly cold backup ended in SIGKILL/137), and the
  add-on now declares `timeout: 60` as extra headroom for loaded shutdowns.
  Measured stop time: 35s → ~9s.
- Smoke test now asserts the recall deadline returns 504 and that
  `docker stop` exits 0 (clean shutdown) — guards both regressions.

## 0.1.1

- Fix the in-sidebar UI: opening a memory bank no longer 404s. The upstream
  control-plane is built with an empty Next.js basePath, so its App Router
  emitted root-absolute navigation/RSC URLs that escaped Home Assistant's
  dynamic ingress prefix. The control-plane is now rebuilt from the pinned
  upstream source with a placeholder basePath, which nginx rewrites to the live
  ingress path; client `fetch()` and public-asset paths are rewritten too.
- Add the Hindsight brand icon (`icon.png`) and logo (`logo.png`); README now
  shows the control-plane UI.

## 0.1.0

- Initial release: Hindsight agent memory (API + control-plane UI + embedded
  pg0) as a Home Assistant add-on. Local embeddings/reranker, OpenRouter
  reasoning LLM, in-sidebar ingress, memory persisted under /data.
