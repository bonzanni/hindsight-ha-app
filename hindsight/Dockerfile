# Hindsight HA add-on — hybrid build.
# Base = HA base-debian:trixie (glibc 2.41). REQUIRED: pg0 downloads a
# PostgreSQL 18 + pgvector bundle at runtime whose vector.so needs GLIBC_2.38+;
# bookworm (glibc 2.36) cannot load it. Upstream itself is python:3.11-slim-trixie
# (Debian 13, glibc 2.41, CPython 3.11.15 in /usr/local) — we mirror that exact
# glibc+python combo. trixie's *system* python is 3.13, so instead of using it we
# COPY upstream's /usr/local CPython 3.11 (cp311 ABI match for the copied wheels).
# Base ships bashio + s6-overlay v3, so config.yaml uses init: false.
ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:trixie-2026.05.0

# Pin the upstream Hindsight image by DIGEST (from RECON-NOTES.md) for
# reproducible COPYs. Bump deliberately.
# !! When bumping this digest, ALSO bump HINDSIGHT_REF (cp-builder, below) to the
#    SAME upstream revision so the rebuilt control-plane matches the COPY-ed API,
#    then re-run tests/run-ingress.sh (the CP's fetch/asset shapes can change).
ARG HINDSIGHT_IMAGE=ghcr.io/vectorize-io/hindsight@sha256:e82b2c051784affa73243108c06402655043999e362bb3b7226b4da1000e1660

FROM ${HINDSIGHT_IMAGE} AS upstream

# ==============================================================================
# Control-plane builder — rebuild the Next.js CP under a PLACEHOLDER basePath.
# Upstream ships the CP built with basePath="" (NEXT_PUBLIC_BASE_PATH unset),
# whose App Router generates root-absolute navigation/RSC URLs that escape HA's
# dynamic ingress prefix (bank pages 404). next.config.ts reads basePath from
# NEXT_PUBLIC_BASE_PATH (a supported "reverse proxy" build arg), so we rebuild
# ONLY the CP, from the SAME pinned upstream revision as HINDSIGHT_IMAGE, with a
# unique literal placeholder. nginx then sub_filters /__HA_INGRESS__ -> the live
# X-Ingress-Path at request time (see hindsight-ingress.conf).
# ==============================================================================
FROM node:20-slim AS cp-builder
# Defaults are set HERE (in-stage), not before the first FROM: an ARG declared
# after a FROM is stage-scoped, so a bare re-declaration resolves to empty.
# Empty HINDSIGHT_REF -> wrong source revision; empty placeholder -> basePath="".
# !! Keep HINDSIGHT_REF in lockstep with the HINDSIGHT_IMAGE digest above (same
#    upstream revision). v0.7.1 = 779e3140; bump both together.
ARG HINDSIGHT_REF=779e3140c8faeb3d6662e64bff7b908e9e29c989
ARG HA_INGRESS_PLACEHOLDER=/__HA_INGRESS__
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --filter=blob:none https://github.com/vectorize-io/hindsight.git /src \
 && git -C /src checkout ${HINDSIGHT_REF}
# Build the TypeScript client SDK the control-plane depends on (workspace build).
WORKDIR /src
RUN npm ci --ignore-scripts -w @vectorize-io/hindsight-client \
 && npm run build -w @vectorize-io/hindsight-client
# Build the control-plane under the monorepo path its build:standalone expects.
# Mirrors upstream docker/standalone/Dockerfile's cp-builder stage.
WORKDIR /app/memory-poc/hindsight-control-plane
RUN cp /src/hindsight-control-plane/package.json ./ \
 && sed -i '/"@vectorize-io\/hindsight-client":/d' package.json \
 && npm install
RUN cp -a /src/hindsight-control-plane/. ./ \
 && rm -f package-lock.json \
 && sed -i '/"@vectorize-io\/hindsight-client":/d' package.json \
 && mkdir -p ./node_modules/@vectorize-io \
 && rm -rf ./node_modules/@vectorize-io/hindsight-client \
 && cp -a /src/hindsight-clients/typescript ./node_modules/@vectorize-io/hindsight-client
ENV NEXT_PUBLIC_BASE_PATH=${HA_INGRESS_PLACEHOLDER}
RUN npm exec -- next build \
 && STANDALONE_ROOT=$(find .next/standalone -path '*/node_modules' -prune -o -name 'server.js' -print | head -1 | xargs dirname) \
 && mkdir -p standalone \
 && cp -r "$STANDALONE_ROOT"/* standalone/ \
 && cp -r "$STANDALONE_ROOT"/.next standalone/.next \
 && if [ -d ".next/standalone/node_modules" ] && [ "$STANDALONE_ROOT" != ".next/standalone" ]; then cp -r .next/standalone/node_modules standalone/node_modules; fi \
 && cp -r .next/static standalone/.next/static \
 && mkdir -p standalone/public && (cp -r public/* standalone/public/ 2>/dev/null || true) \
 && test -f standalone/server.js && test -f standalone/.next/BUILD_ID

FROM ${BUILD_FROM}

LABEL org.opencontainers.image.source="https://github.com/bonzanni/hindsight-ha-app" \
      org.opencontainers.image.title="Hindsight" \
      org.opencontainers.image.description="Agent memory (Hindsight) for Home Assistant" \
      org.opencontainers.image.licenses="MIT"

# Runtime deps: nginx + Node 20, the API's native libs, and the shared libraries
# the COPY-ed python.org CPython 3.11 links against (ssl/ffi/sqlite/bz2/lzma/
# ncurses/readline/uuid/gdbm/expat). On trixie these provide the .so deps the
# /usr/local interpreter needs; without them `import ssl`/`sqlite3` etc. fail.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl procps nginx patch \
      libxml2 libssl3 libgssapi-krb5-2 libossp-uuid16 \
      libffi8 libsqlite3-0 libbz2-1.0 liblzma5 libncursesw6 \
      libreadline8 zlib1g libuuid1 libgdbm6 libexpat1 \
 && (apt-get install -y --no-install-recommends libicu76 || apt-get install -y --no-install-recommends libicu72 || true) \
 && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default

# Non-root user for the app + embedded Postgres (pg0 refuses to run as root).
RUN useradd -m -s /bin/bash hindsight

# Bring prebuilt artifacts from the upstream image.
COPY --from=upstream /app/api /app/api
COPY --from=upstream /app/start-all.sh /app/start-all.sh

# Patch the COPY-ed API (editable install -> source lives at /app/api/hindsight_api):
# recall handler deadline + configurable worker drain timeout + reranker-lane
# contention control. See each patch header for rationale. patch(1) fails the
# build if the pinned source drifts, so a HINDSIGHT_IMAGE bump that
# invalidates a patch cannot ship silently.
COPY patches/recall-deadline-worker-drain.patch patches/rerank-contention.patch /tmp/hindsight-patches/
RUN patch -p1 -d /app/api < /tmp/hindsight-patches/recall-deadline-worker-drain.patch \
 && patch -p1 -d /app/api < /tmp/hindsight-patches/rerank-contention.patch \
 && rm -rf /tmp/hindsight-patches

# Control-plane: the placeholder-basePath rebuild (cp-builder), NOT the upstream
# image's basePath="" build. Layout mirrors upstream's cp-only stage.
COPY --from=cp-builder /app/memory-poc/hindsight-control-plane/standalone /app/control-plane
COPY --from=cp-builder /app/memory-poc/hindsight-control-plane/.next/static /app/control-plane/.next/static
COPY --from=cp-builder /app/memory-poc/hindsight-control-plane/public /app/control-plane/public

# Preloaded HuggingFace model cache (embeddings + reranker).
# Models confirmed in RECON-NOTES.md:
#   /home/hindsight/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5
#   /home/hindsight/.cache/huggingface/hub/models--cross-encoder--ms-marco-MiniLM-L-6-v2
COPY --from=upstream /home/hindsight/.cache /opt/hindsight/cache

# tiktoken cl100k_base blob lives at /tmp/data-gym-cache in the upstream image
# (NOT under /home/hindsight/.cache — confirmed in RECON-NOTES.md §4c).
# TIKTOKEN_CACHE_DIR below points the library here at runtime.
COPY --from=upstream /tmp/data-gym-cache /opt/hindsight/cache/tiktoken

# Bring upstream's CPython 3.11 (the official python:3.11-slim /usr/local layout)
# so the cp311 venv runs on trixie, whose system python is 3.13. The venv's
# pyvenv.cfg has home=/usr/local/bin and bin/python -> /usr/local/bin/python3,
# so recreating /usr/local exactly like upstream means the venv works unchanged
# (no interpreter symlink rewrite needed). ldconfig picks up libpython3.11.so.
COPY --from=upstream /usr/local/bin/python3.11 /usr/local/bin/python3.11
COPY --from=upstream /usr/local/bin/python3.11-config /usr/local/bin/python3.11-config
COPY --from=upstream /usr/local/lib/python3.11 /usr/local/lib/python3.11
COPY --from=upstream /usr/local/lib/libpython3.11.so.1.0 /usr/local/lib/libpython3.11.so.1.0
COPY --from=upstream /usr/local/lib/libpython3.so /usr/local/lib/libpython3.so
RUN ln -sf python3.11 /usr/local/bin/python3 \
 && ln -sf python3 /usr/local/bin/python \
 && ldconfig

# Caches: offline, and OUT of /data (which is an empty volume on first run).
#
# SENTENCE_TRANSFORMERS_HOME is intentionally NOT set. Source evidence:
#   - embeddings.py line 225: SentenceTransformer(self.model_name, device=device, ...)
#   - cross_encoder.py line 274: CrossEncoder(self.model_name, device=device, ...)
# Neither call passes a cache_folder argument, so sentence-transformers delegates
# model resolution to huggingface_hub.snapshot_download, which uses HF_HOME.
# Setting SENTENCE_TRANSFORMERS_HOME would redirect to a different (nonexistent)
# directory and break offline loading. HF_HOME alone is sufficient.
ENV HF_HOME=/opt/hindsight/cache/huggingface \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    TIKTOKEN_CACHE_DIR=/opt/hindsight/cache/tiktoken \
    PATH=/app/api/.venv/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONUNBUFFERED=1 \
    NODE_ENV=production \
    TRANSFORMERS_VERBOSITY=error \
    HF_HUB_VERBOSITY=error \
    TOKENIZERS_PARALLELISM=false \
    HINDSIGHT_API_HOST=0.0.0.0 \
    HINDSIGHT_API_PORT=8888 \
    HINDSIGHT_CP_DATAPLANE_API_URL=http://localhost:8888

# s6-overlay shutdown grace. WAL safety comes from the ORDERED service stop
# (s6-rc waits for hindsight-app; start-all.sh forwards TERM and waits for the
# API to drain + stop pg0 — measured ~4s idle). S6_KILL_GRACETIME is only the
# stage-3 TERM->KILL sweep for stragglers, and s6 sits out the FULL value
# before exiting: at the previous 30000 the container needed 35s to stop, so
# the Supervisor's stop grace expired first -> SIGKILL (exit 137) on every
# nightly cold backup even when idle. 5s is ample for stragglers.
# S6_SERVICES_GRACETIME only applies to legacy /etc/services.d (unused here).
ENV S6_KILL_GRACETIME=5000 \
    S6_SERVICES_GRACETIME=10000

# Recall-latency + shutdown tuning for the target host class (N150: 4 E-cores,
# CPU-only). Measured on-device at v0.1.1: reranking 300 pairs took ~6.3s idle
# and ~25s each for two concurrent recalls (47 threads — every torch predict
# spawns its own ~4-thread OpenMP team), blowing consumers' 20s client budget.
#   OMP_WAIT_POLICY:            stop libgomp idle-spin burn between batches
#   RERANKER_MAX_CANDIDATES:    rerank depth cap 300 -> 100 (~3x less CPU;
#                               final top-k comes from RRF top-100)
#   BUCKET_BATCHING:            upstream opt-in, length-sorted batches,
#                               quality-identical, 36-54% faster
#   LOCAL_MAX_CONCURRENT=1:     serialize cross-encoder calls — one rerank
#                               gets all 4 cores; no thread-thrash collapse
#   CONSOLIDATION_MAX_SLOTS=1:  at most one background consolidation competing
#   RECALL_HANDLER_TIMEOUT=15:  fail recalls fast (504) before the consumer's
#                               20s aiohttp budget (patched-in, see patches/)
#   WORKER_SHUTDOWN_TIMEOUT=8:  short worker drain so add-on stop beats the
#                               Supervisor kill grace (patched-in)
#   CONSOLIDATION_RECALL_RERANKER=rrf: consolidation's internal recalls (one
#                               per fact, in parallel — measured recall=284s
#                               per batch) skip the serialized cross-encoder
#                               lane entirely (RRF ordering; upstream's
#                               is_passthrough scoring path), so background
#                               consolidation can't starve interactive
#                               recalls (patched-in, see patches/)
#   RERANKER_BUSY_PASSTHROUGH_THRESHOLD=2: one 100-pair rerank is ~6.5s on
#                               this host, so an interactive recall queueing
#                               behind >=2 unfinished jobs would blow the 15s
#                               handler deadline; it degrades to RRF ordering
#                               instead of 504ing (patched-in)
ENV OMP_WAIT_POLICY=PASSIVE \
    HINDSIGHT_API_RERANKER_MAX_CANDIDATES=100 \
    HINDSIGHT_API_RERANKER_LOCAL_BUCKET_BATCHING=true \
    HINDSIGHT_API_RERANKER_LOCAL_MAX_CONCURRENT=1 \
    HINDSIGHT_API_WORKER_CONSOLIDATION_MAX_SLOTS=1 \
    HINDSIGHT_API_RECALL_HANDLER_TIMEOUT=15 \
    HINDSIGHT_API_WORKER_SHUTDOWN_TIMEOUT=8 \
    HINDSIGHT_API_CONSOLIDATION_RECALL_RERANKER=rrf \
    HINDSIGHT_API_RERANKER_BUSY_PASSTHROUGH_THRESHOLD=2

RUN chown -R hindsight:hindsight /app /opt/hindsight

# Build-time smoke: the copied venv must import on this base's python3.11.
RUN /app/api/.venv/bin/python -c "import torch, sentence_transformers, hindsight_api; print('venv import OK')"

# Build-time smoke: the patched modules must import (syntax) and actually
# contain the patched-in env knobs (guards against a partial patch apply).
RUN /app/api/.venv/bin/python -c "\
import inspect; \
import hindsight_api.api.http as m; \
src = inspect.getsource(m); \
assert 'HINDSIGHT_API_RECALL_HANDLER_TIMEOUT' in src, 'recall deadline patch missing'; \
assert 'HINDSIGHT_API_WORKER_SHUTDOWN_TIMEOUT' in src, 'worker drain patch missing'; \
import hindsight_api.engine.memory_engine as me; \
esrc = inspect.getsource(me); \
assert 'HINDSIGHT_API_CONSOLIDATION_RECALL_RERANKER' in esrc, 'consolidation passthrough patch missing'; \
assert 'HINDSIGHT_API_RERANKER_BUSY_PASSTHROUGH_THRESHOLD' in esrc, 'busy-degrade patch missing'; \
import hindsight_api.engine.cross_encoder as ce; \
assert 'def pending_jobs' in inspect.getsource(ce), 'reranker occupancy patch missing'; \
import hindsight_api.engine.consolidation.consolidator as cc; \
assert '_RERANK_PASSTHROUGH_CTX' in inspect.getsource(cc), 'consolidation ctx patch missing'; \
print('patched modules OK')"

# Build-time smoke: the rerank occupancy accounting must survive queued-job
# cancellation, running-job cancellation, and worker exceptions without
# leaking (reviewer-required regression for the busy-degrade counter; the
# leaked counter failure mode is permanent degraded ranking until restart).
COPY build-smoke/rerank_occupancy_smoke.py /tmp/build-smoke/
RUN /app/api/.venv/bin/python /tmp/build-smoke/rerank_occupancy_smoke.py \
 && rm -rf /tmp/build-smoke

# Build-time smoke: load embedding model offline from baked HF cache.
# SentenceTransformer resolves via HF_HOME (no cache_folder arg in upstream source).
# With HF_HUB_OFFLINE=1, this MUST succeed from cache — no network access.
RUN /app/api/.venv/bin/python -c "\
from sentence_transformers import SentenceTransformer; \
m = SentenceTransformer('BAAI/bge-small-en-v1.5'); \
v = m.encode(['hello']); \
assert len(v[0]) > 0, 'embedding vector is empty'; \
print('embeddings offline OK')"

# Build-time smoke: load reranker model offline from baked HF cache.
# CrossEncoder resolves via HF_HOME (no cache_folder arg in upstream source).
RUN /app/api/.venv/bin/python -c "\
from sentence_transformers import CrossEncoder; \
m = CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2'); \
scores = m.predict([('what is AI', 'AI is artificial intelligence')]); \
assert len(scores) == 1, 'reranker returned no scores'; \
print('reranker offline OK')"

# Build-time smoke: tiktoken cl100k_base blob must be present and loadable.
RUN /app/api/.venv/bin/python -c "\
import tiktoken; \
enc = tiktoken.get_encoding('cl100k_base'); \
tokens = enc.encode('hello'); \
assert len(tokens) > 0, 'tiktoken returned no tokens'; \
print('tiktoken offline OK')"

# s6 services + nginx config.
COPY rootfs /

# Restore exec bits (Windows/WSL checkouts can drop them).
RUN chmod +x /etc/s6-overlay/scripts/*.sh \
 && find /etc/s6-overlay/s6-rc.d \( -name run -o -name finish -o -name up \) -exec chmod +x {} +

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 CMD curl -fsS http://127.0.0.1:8888/health >/dev/null || exit 1

EXPOSE 8888 8099
