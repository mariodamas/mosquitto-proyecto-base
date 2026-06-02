#!/usr/bin/env python3
"""Publish DevSecOps platform notification events from Jenkins.

The Jenkinsfile should only orchestrate. This helper owns payload shaping,
metadata loading and optional authentication for the DevSecOps API.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Notify DevSecOps API about a completed Jenkins job")
    parser.add_argument("--job-key", required=True, choices=["general", "monitoring"])
    parser.add_argument("--default-job-name", required=True)
    parser.add_argument("--trigger-type", required=True)
    parser.add_argument("--metadata-file", action="append", default=[])
    parser.add_argument("--metadata-glob", action="append", default=[])
    parser.add_argument("--api-base-url", default=os.environ.get("DEVSECOPS_API_BASE_URL"))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    api_base = (args.api_base_url or "").rstrip("/")
    if not api_base:
        print("DevSecOps notification skipped: DEVSECOPS_API_BASE_URL is not set")
        return 0

    metadata_paths = _collect_metadata_paths(args.metadata_file, args.metadata_glob)
    metadata_items = [_load_metadata(path) for path in metadata_paths] or [{}]

    for metadata in metadata_items:
        _publish(api_base, _payload(args, metadata))
    return 0


def _collect_metadata_paths(files: list[str], patterns: list[str]) -> list[Path]:
    paths: list[Path] = []
    for raw_path in files:
        path = Path(raw_path)
        if path.exists():
            paths.append(path)
    for pattern in patterns:
        paths.extend(Path(match) for match in glob.glob(pattern, recursive=True))
    return sorted({path.resolve(): path for path in paths}.values())


def _load_metadata(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"WARNING: could not read DevSecOps metadata {path}: {exc}")
        return {}


def _payload(args: argparse.Namespace, metadata: dict[str, Any]) -> dict[str, Any]:
    build_number = os.environ.get("BUILD_NUMBER") or os.environ.get("BUILD_ID") or os.environ.get("RUN_ID")
    return {
        "job_key": args.job_key,
        "jenkins_job_name": os.environ.get("JOB_NAME") or args.default_job_name,
        "build_number": int(build_number) if build_number and build_number.isdigit() else None,
        "build_url": os.environ.get("BUILD_URL") or None,
        "result": os.environ.get("JENKINS_RESULT") or "UNKNOWN",
        "project_id": metadata.get("project_id"),
        "execution_id": metadata.get("execution_id"),
        "trigger_type": args.trigger_type,
    }


def _publish(api_base: str, payload: dict[str, Any]) -> bool:
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    token = os.environ.get("DEVSECOPS_API_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(
        f"{api_base}/pipeline/events/jenkins-completed",
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            print(f"DevSecOps notification event published: HTTP {response.status}")
        return True
    except urllib.error.URLError as exc:
        print(f"WARNING: could not publish DevSecOps notification event: {exc}")
        return False


if __name__ == "__main__":
    raise SystemExit(main())
