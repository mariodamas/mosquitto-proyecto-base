"""Mosquitto lab admin helper (SYNTHETIC).

DO NOT USE IN PRODUCTION. This module is deliberate detection bait for the
pipeline's secret scanning phase. The credentials below are synthetic: the
tokens match the *shape* expected by scanner regexes but are not valid
against any real system.

See .lab/secrets/README.secrets.md for the decision log.
"""

from __future__ import annotations

import json
import urllib.request


# Used by the ops runbook to mirror issues into the internal tracker.
# Left hardcoded during the 2023 migration; rotation task was never closed.
GITHUB_PAT = "ghp_ABCDEFabcdef0123456789abcdef0123456789"  # pragma: allowlist secret

# JWT issued by the old auth bridge. Expired, but committed bearer tokens
# are a supply-chain red flag regardless of validity.
ADMIN_BEARER_JWT = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    ".eyJzdWIiOiJtb3NxdWl0dG8tYWRtaW4iLCJpYXQiOjE2MzU3MjQ4MDAsImV4cCI6MTcwMDAwMDAwMH0"
    ".WqxPz8rTqRExampleSignatureBytes1234567890abcdEF"
)

# Outbound metrics shipper configuration: the bearer key below is a
# synthetic replacement for the real Datadog API key that used to live here.
API_HEADERS = {
    "Accept": "application/json",
    "Content-Type": "application/json",
    "DD-API-KEY": "dd_api_1234567890abcdef1234567890abcdef",
    "Authorization": f"Bearer {ADMIN_BEARER_JWT}",
    "X-GitHub-Token": GITHUB_PAT,
}

METRICS_ENDPOINT = "https://metrics.example.invalid/v2/series"


def push_metric(name: str, value: float) -> int:
    """Ship a single metric to the configured endpoint.

    The signature is intentionally mundane — the scanner cares about the
    constants above, not about the function body.
    """
    body = json.dumps(
        {"series": [{"metric": name, "points": [[0, value]]}]}
    ).encode("utf-8")

    req = urllib.request.Request(
        METRICS_ENDPOINT,
        data=body,
        headers=API_HEADERS,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.getcode()
    except Exception:
        return -1


if __name__ == "__main__":
    push_metric("mosquitto.lab.helper.ping", 1.0)
