#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

require_text() {
  local file=$1
  local pattern=$2
  local description=$3

  if ! grep -Eq "$pattern" "$file"; then
    printf 'FAIL: %s (%s)\n' "$description" "$file" >&2
    return 1
  fi
}

require_text README.md 'prebuilt' 'README must explain prebuilt installation'
require_text README.md 'Cosign-signed' 'README must identify the signed artifact'
require_text README.md 'ghcr\.io/bonzanni/hindsight' 'README must name the published image'
require_text README.md 'amd64' 'README must retain the amd64-only support boundary'
require_text README.md 'docker build -t hindsight-addon:dev hindsight/' 'README must document direct local builds'
require_text README.md 'TEST_IMAGE=ghcr\.io/bonzanni/hindsight:0\.3\.0' 'README must document exact-artifact harness testing'

require_text hindsight/DOCS.md 'prebuilt' 'app docs must explain prebuilt installation'
require_text hindsight/DOCS.md 'Cosign-signed' 'app docs must identify the signed artifact'
require_text hindsight/DOCS.md 'ghcr\.io/bonzanni/hindsight' 'app docs must name the published image'
require_text hindsight/DOCS.md 'amd64' 'app docs must retain the amd64-only support boundary'
require_text hindsight/DOCS.md 'options remain managed by Supervisor' 'app docs must state option preservation'

require_text hindsight/CHANGELOG.md '^## 0\.3\.0$' 'changelog must contain the exact automated-release heading'
require_text CLAUDE.md 'auto-publishes.*GHCR|GHCR.*auto-publishes' 'contributor guide must describe main-branch publication'
require_text CLAUDE.md 'no manual tagging|Do not tag manually' 'contributor guide must remove the manual tag step'

require_text hindsight/APPARMOR_ACCEPTANCE.md '5884eb17_hindsight' 'acceptance procedure must name the expected profile'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'SIGCONT' 'acceptance procedure must exercise harmless signalling'
require_text hindsight/APPARMOR_ACCEPTANCE.md '30 seconds' 'acceptance procedure must enforce the shutdown limit'
require_text hindsight/APPARMOR_ACCEPTANCE.md '0\.2\.2' 'acceptance procedure must baseline the existing version'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'redacted-options SHA-256' 'acceptance procedure must compare options without exposing secrets'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'not print or attach the credential' 'acceptance procedure must protect the OpenRouter key'
require_text hindsight/APPARMOR_ACCEPTANCE.md '\.State\.Running=false' 'acceptance procedure must poll actual container shutdown'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'container exit code.*0' 'acceptance procedure must require clean exit code zero'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'API health and ingress success' 'acceptance procedure must retest health and ingress'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'pre-update memory-bank' 'acceptance procedure must verify the data sentinel'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'PG_VERSION' 'acceptance procedure must verify persisted pg0 data'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'no AppArmor denial related to signalling, s6 shutdown' 'acceptance procedure must reject relevant denials'
require_text hindsight/APPARMOR_ACCEPTANCE.md '[Ee]xceptional' 'cache recovery must be explicitly exceptional'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'genuinely pending newer' 'cache recovery must require an update that can recompile'
require_text hindsight/APPARMOR_ACCEPTANCE.md 'subsequent patch' 'latest-version failure must require a new release'

require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md 'signal \(send\),' 'reproducer must include the old profile rule'
require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md 'signal \(send,receive\),' 'reproducer must include the new profile rule'
require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md '/data/apparmor/cache/.*/5884eb17_hindsight' 'reproducer must include the observed cache path'
require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md 'Supervisor 2026\.06\.2' 'reproducer must record the observed Supervisor version'
require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md 'HAOS 18\.1' 'reproducer must record the observed HAOS version'
require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md 'docker inspect --format.*AppArmorProfile' 'reproducer must record the loaded profile name'
require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md 'remove only' 'reproducer must scope cache removal to one profile'
require_text hindsight/SUPERVISOR_APPARMOR_REPRODUCER.md 'pending newer version' 'reproducer must identify the recompiling update condition'

echo 'documentation release contract: PASS'
