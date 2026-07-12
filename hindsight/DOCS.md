# Hindsight for Home Assistant

Hindsight is an agent memory add-on for Home Assistant. It gives AI agents a
persistent, queryable memory store backed by a local vector database and an
embedded PostgreSQL instance. Agents call the Hindsight API to retain facts and
to recall them later; Hindsight handles embedding, storage, and reasoning
entirely on your Home Assistant host.

## Requirements

- **Architecture**: amd64
- **RAM**: 2 GB minimum; 4 GB recommended when the reranker is enabled
- **Storage**: 1 GB base + data growth
- **OpenRouter account**: Required — get a key at https://openrouter.ai

## Configuration

### OpenRouter API Key (required)

- **openrouter_api_key**: Your OpenRouter API key. Hindsight uses OpenRouter
  for its reasoning steps (fact extraction on retain, dialectic reasoning on
  recall). The add-on will not start without a valid key.

### Reasoning Model

- **llm_model**: OpenRouter model ID used for all reasoning steps. Default is
  `google/gemini-2.5-flash`, which balances speed and cost well for most
  workloads. Change this to any model available on OpenRouter.
- **llm_reasoning_effort**: Effort hint passed to models that support it.
  `low` (default) is fastest; `medium` and `high` trade latency for more
  thorough reasoning. Ignored by models that do not support the hint.

### Performance Toggles

- **reranker_enabled**: When `true` (default), Hindsight runs a local
  cross-encoder model to rerank candidates before returning recall results.
  This improves recall quality at the cost of a small latency increase.
  Disable on low-power hosts where the extra compute is unacceptable.
- **enable_ui**: When `true` (default), Hindsight serves a control-plane
  memory-browser UI accessible from the Home Assistant sidebar. Disable for a
  headless, API-only deployment; this reduces the add-on's memory footprint
  slightly.

### Logging

- **log_level**: Controls application log verbosity. One of `debug`, `info`
  (default), `warning`, `error`, or `critical`.

## Recall Latency and the `budget` Parameter

The add-on is tuned for low-power CPU-only hosts (e.g. Intel N150):

- The recall `budget` request parameter (`low`/`mid`/`high`) controls
  *retrieval breadth* — how many candidates each retrieval method fetches
  (100/300/1000).
- Reranking depth is capped separately at **100 candidates** (the RRF
  top-100), regardless of `budget`. On a grown memory bank all budgets
  therefore cost roughly the same in rerank CPU; pick `budget` by how wide
  you want retrieval to look, not by latency.
- A recall that cannot complete within **15 seconds** returns HTTP 504
  instead of silently overrunning. Design API clients with a timeout a few
  seconds above that (e.g. 20s) and treat 504 as "degrade now, retry later".

Expected recall latency on an N150-class host at a few-thousand-memory bank:
~2-4s, worst case under concurrent background work well below 15s.

## Sidebar UI

When `enable_ui` is enabled the Hindsight memory browser appears as a sidebar
panel (brain icon). Use it to inspect stored memories, browse the knowledge
graph, and manually delete entries. No separate browser tab is required.

## Network Access

Other Home Assistant add-ons can reach the Hindsight API on the internal Docker
network at:

```
http://hindsight:8888
```

Use this URL when configuring agent add-ons or MCP servers that need to read
from or write to Hindsight memory. The API is also optionally exposed on the
host network via port 8888 (set a host port in the add-on network configuration
to enable LAN access).

The `/health` endpoint is used by the Supervisor watchdog and can also be polled
by dependent add-ons to verify Hindsight is ready.

## Data Persistence and Backups

All memory data — the vector store and the embedded PostgreSQL database — is
stored under `/data` on the add-on's persistent volume. This
directory is included in Home Assistant cold backups automatically. Restore a
backup to move the entire memory store to a new host.
