# Changelog

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
