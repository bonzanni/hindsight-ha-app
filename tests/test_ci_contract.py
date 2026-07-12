#!/usr/bin/env python3
"""Static contract for the prebuilt-image publishing pipeline."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    target = ROOT / path
    return target.read_text(encoding="utf-8") if target.exists() else ""


class PublishingWorkflowContract(unittest.TestCase):
    def assert_patterns(self, text: str, patterns: dict[str, str]) -> None:
        missing = [
            label
            for label, pattern in patterns.items()
            if not re.search(pattern, text, re.MULTILINE | re.DOTALL)
        ]
        self.assertFalse(missing, "missing contract clauses: " + ", ".join(missing))

    def test_deploy_workflow_is_safe_and_release_gated(self) -> None:
        workflow = read(".github/workflows/deploy.yml")
        self.assert_patterns(
            workflow,
            {
                "main push trigger": r"push:\s+branches:\s*\[main\]",
                "PR trigger": r"pull_request:",
                "narrow app path": r'["\']hindsight/\*\*["\']',
                "narrow workflow path": r'["\']\.github/workflows/deploy\.yml["\']',
                "read-only workflow default": r"(?m)^permissions:\s*\n\s+contents:\s*read\s*$",
                "serialized publication": r"concurrency:.*cancel-in-progress:\s*false",
                "HA metadata helper": r"home-assistant/actions/helpers/info@master",
                "label metadata read from config": r"read_config_scalar name.*read_config_scalar description.*read_config_scalar url",
                "strict semantic version": r"\^\(0\|\[1-9\]\[0-9\]\*\)\\\.\(0\|\[1-9\]\[0-9\]\*\)\\\.\(0\|\[1-9\]\[0-9\]\*\)\$",
                "fixed image repository": r"ghcr\.io/bonzanni/hindsight",
                "amd64 matrix": r"prepare-multi-arch-matrix@2026\.06\.0",
                "PR build does not push": r"build_pr:.*build-image@2026\.06\.0.*push:\s*false",
                "publish build permissions": r"build_publish:.*permissions:.*contents:\s*read.*packages:\s*write.*id-token:\s*write",
                "versioned and latest tags": r"image-tags:\s*\|\s*\n\s*\$\{\{[^\n]*version[^\n]*\}\}\s*\n\s*latest",
                "HA type label": r"io\.hass\.type=app",
                "HA name label": r"io\.hass\.name=",
                "HA description label": r"io\.hass\.description=",
                "HA URL label": r"io\.hass\.url=",
                "signed generic manifest": r"publish-multi-arch-manifest@2026\.06\.0",
                "verification after manifest": r"verify:.*needs:.*manifest",
                "current Cosign installer": r"sigstore/cosign-installer@v4\.1\.2",
                "exact platform verification": r'\.platform\.os == "linux".*\.platform\.architecture == "amd64"',
                "provenance descriptors handled": r'\.platform\.os == "unknown".*\.platform\.architecture == "unknown"',
                "attestation descriptors identified": r'vnd\.docker\.reference\.type.*attestation-manifest',
                "attestations tied to image digest": r'vnd\.docker\.reference\.digest.*image_digest',
                "generic digest comparison": r"DIGEST_.*VERSION.*DIGEST_.*LATEST|version_digest.*latest_digest",
                "image label inspection": r"imagetools inspect.*--format",
                "Cosign keyless verification": r"cosign verify.*--certificate-identity-regexp.*--certificate-oidc-issuer",
                "generic and per-arch references verified": r"cosign verify[\s\S]*VERSION_REF[\s\S]*cosign verify[\s\S]*ARCH_REF",
                "release gated on verification": r"release:.*needs:.*verify",
                "release write permission": r"release:.*permissions:\s*\n\s+contents:\s*write",
                "exact changelog section": r'\$0 == "## " ver.*hindsight/CHANGELOG\.md',
                "conflicting tag rejected": r"tag.*different commit|different commit.*tag",
                "public tag author name": r'git config user\.name "bonzanni"',
                "public tag author email": r'git config user\.email "3899230\+bonzanni@users\.noreply\.github\.com"',
                "annotated tag": r"git tag -a",
                "idempotent release lookup": r"gh release view",
                "GitHub release creation": r"gh release create",
            },
        )

    def test_lint_workflow_keeps_existing_checks_and_adds_ha_and_apparmor(self) -> None:
        workflow = read(".github/workflows/lint.yml")
        self.assert_patterns(
            workflow,
            {
                "hadolint retained": r"hadolint/hadolint-action@",
                "ShellCheck retained": r"shellcheck -s bash",
                "all public shell tests linted": r"find tests .*name ['\"]\\?\*\.sh",
                "HA app linter": r"frenck/action-addon-linter@v2\.21",
                "AppArmor parser": r"apparmor_parser -Q",
                "signal send required": r"signal.*send",
                "signal receive required": r"signal.*receive",
                "packaging and docs contracts run": r"make contracts",
                "static CI contract runs": r"python3 tests/test_ci_contract\.py",
            },
        )

    def test_dependabot_tracks_github_actions_weekly(self) -> None:
        dependabot = read(".github/dependabot.yml")
        self.assert_patterns(
            dependabot,
            {
                "v2 config": r"(?m)^version:\s*2\s*$",
                "GitHub Actions ecosystem": r'package-ecosystem:\s*["\']github-actions["\']',
                "repository root": r'directory:\s*["\']/["\']',
                "weekly interval": r"interval:\s*weekly",
            },
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
