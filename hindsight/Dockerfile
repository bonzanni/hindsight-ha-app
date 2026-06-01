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
ARG HINDSIGHT_IMAGE=ghcr.io/vectorize-io/hindsight@sha256:e82b2c051784affa73243108c06402655043999e362bb3b7226b4da1000e1660

FROM ${HINDSIGHT_IMAGE} AS upstream

FROM ${BUILD_FROM}

# Runtime deps: nginx + Node 20, the API's native libs, and the shared libraries
# the COPY-ed python.org CPython 3.11 links against (ssl/ffi/sqlite/bz2/lzma/
# ncurses/readline/uuid/gdbm/expat). On trixie these provide the .so deps the
# /usr/local interpreter needs; without them `import ssl`/`sqlite3` etc. fail.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl procps nginx \
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
