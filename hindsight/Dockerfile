# Hindsight HA add-on — hybrid build.
# Base = HA base-debian:bookworm -> Python 3.11, matching the upstream venv's
# cp311 ABI (trixie ships 3.13 and would break the copied wheels). Ships
# bashio + s6-overlay v3, so config.yaml uses init: false.
ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:bookworm

# Pin the upstream Hindsight image by DIGEST (from RECON-NOTES.md) for
# reproducible COPYs. Bump deliberately.
ARG HINDSIGHT_IMAGE=ghcr.io/vectorize-io/hindsight@sha256:e82b2c051784affa73243108c06402655043999e362bb3b7226b4da1000e1660

FROM ${HINDSIGHT_IMAGE} AS upstream

FROM ${BUILD_FROM}

# Runtime deps mirrored from the upstream standalone stage, plus nginx + Node 20.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl procps nginx \
      libxml2 libssl3 libgssapi-krb5-2 libossp-uuid16 \
 && (apt-get install -y --no-install-recommends libicu72 || true) \
 && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default

# Non-root user for the app + embedded Postgres (pg0 refuses to run as root).
RUN useradd -m -s /bin/bash hindsight

# Bring prebuilt artifacts from the upstream image.
COPY --from=upstream /app/api /app/api
COPY --from=upstream /app/control-plane /app/control-plane
COPY --from=upstream /app/start-all.sh /app/start-all.sh

# Preloaded HuggingFace model cache (embeddings + reranker).
# Models confirmed in RECON-NOTES.md:
#   /home/hindsight/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5
#   /home/hindsight/.cache/huggingface/hub/models--cross-encoder--ms-marco-MiniLM-L-6-v2
COPY --from=upstream /home/hindsight/.cache /opt/hindsight/cache

# tiktoken cl100k_base blob lives at /tmp/data-gym-cache in the upstream image
# (NOT under /home/hindsight/.cache — confirmed in RECON-NOTES.md §4c).
# TIKTOKEN_CACHE_DIR below points the library here at runtime.
COPY --from=upstream /tmp/data-gym-cache /opt/hindsight/cache/tiktoken

# Re-point the venv interpreter at bookworm's python3.11 (upstream slim builder
# placed it under /usr/local/bin; this HA base has it at /usr/bin).
RUN ln -sf /usr/bin/python3.11 /app/api/.venv/bin/python \
 && ln -sf python /app/api/.venv/bin/python3 \
 && ln -sf python /app/api/.venv/bin/python3.11

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
    PATH=/app/api/.venv/bin:/usr/bin:/bin:/usr/local/bin \
    PYTHONUNBUFFERED=1 \
    NODE_ENV=production \
    TRANSFORMERS_VERBOSITY=error \
    HF_HUB_VERBOSITY=error \
    TOKENIZERS_PARALLELISM=false \
    HINDSIGHT_API_HOST=0.0.0.0 \
    HINDSIGHT_API_PORT=8888 \
    HINDSIGHT_CP_DATAPLANE_API_URL=http://localhost:8888 \
    S6_KILL_GRACETIME=30000 \
    S6_SERVICES_GRACETIME=30000

RUN chown -R hindsight:hindsight /app /opt/hindsight

# Build-time smoke: the copied venv must import on this base's python3.11.
RUN /app/api/.venv/bin/python -c "import torch, sentence_transformers, hindsight_api; print('venv import OK')"

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

EXPOSE 8888 8099
