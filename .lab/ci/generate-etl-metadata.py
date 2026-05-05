#!/usr/bin/env python3
"""Generate stable ETL metadata for CI and offline reanalysis snapshots."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def bool_env(name: str, default: bool = False) -> bool:
    value = env(name)
    if value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def run_text(cmd: List[str]) -> str:
    try:
        return subprocess.check_output(
            cmd,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""


def version(cmd: List[str]) -> str:
    try:
        out = subprocess.check_output(
            cmd,
            text=True,
            stderr=subprocess.STDOUT,
        ).splitlines()
    except Exception:
        return "unknown"
    return out[0].strip() if out else "unknown"


def sha256_or_empty(path: Path) -> str:
    if not path.is_file() or path.stat().st_size == 0:
        return ""

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def size_or_zero(path: Path) -> int:
    return path.stat().st_size if path.is_file() else 0


def read_json(path: Path) -> Dict[str, Any]:
    if not path.is_file() or path.stat().st_size == 0:
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def read_int(path: Path) -> Optional[int]:
    if not path.is_file():
        return None
    try:
        return int(path.read_text(encoding="utf-8", errors="replace").strip())
    except Exception:
        return None


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def validate_json_if_present(path: Path) -> None:
    if path.is_file() and path.stat().st_size > 0:
        json.loads(path.read_text(encoding="utf-8"))


def validate_cyclonedx_if_present(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("bomFormat") != "CycloneDX":
        raise SystemExit(f"Not a CycloneDX document: {path}")


def status_for_file(results: Path, relative: str) -> str:
    path = results / relative
    return "success" if path.is_file() and path.stat().st_size > 0 else "skipped"


def exit_for_file(results: Path, relative: str) -> Optional[int]:
    return 0 if status_for_file(results, relative) == "success" else None


def status_for_dir(results: Path, relative: str) -> str:
    path = results / relative
    return "success" if path.is_dir() and any(path.iterdir()) else "skipped"


def exit_for_dir(results: Path, relative: str) -> Optional[int]:
    return 0 if status_for_dir(results, relative) == "success" else None


def first_non_empty(*values: str) -> str:
    for value in values:
        if value:
            return value
    return ""


def add_inventory(
    inventories: List[Dict[str, Any]],
    snapshot: Path,
    dest: Path,
    inventory_id: str,
    logical_name: str,
    relative: str,
    origin: str,
    source_type: str,
    scope: str,
    detection_phase: str,
    required: bool,
) -> None:
    src = snapshot / "raw" / "results" / relative
    inventories.append(
        {
            "id": inventory_id,
            "logical_name": logical_name,
            "path": str(dest / "raw" / "results" / relative),
            "origin": origin,
            "source_type": source_type,
            "scope": scope,
            "artifact_type": "SBOM",
            "detection_phase": detection_phase,
            "required": required,
            "sha256": sha256_or_empty(src),
            "size_bytes": size_or_zero(src),
        }
    )


def tool_run(
    results: Path,
    run_key: str,
    tool_name: str,
    tool_version: str,
    status: str,
    exit_code: Optional[int],
    command_summary: str,
) -> Dict[str, Any]:
    return {
        "run_key": run_key,
        "tool_name": tool_name,
        "tool_version": tool_version,
        "status": status,
        "exit_code": exit_code,
        "command_summary": command_summary,
    }


def build_tool_runs(results: Path) -> Dict[str, Any]:
    emba_exit = read_int(results / "emba" / "emba-exit-code.txt")
    hardening_artifact = env("HARDENING_ARTIFACT", env("BUILD_ARTIFACT", "project artifact"))

    runs = [
        tool_run(
            results,
            "codeql",
            "codeql",
            version(["/opt/codeql/codeql/codeql", "version"]),
            status_for_file(results, "sast/codeql.sarif"),
            exit_for_file(results, "sast/codeql.sarif"),
            "codeql database analyze",
        ),
        tool_run(
            results,
            "coverity/sast",
            "coverity-standard",
            version(["/opt/coverity/bin/cov-analyze", "--version"]),
            status_for_file(results, "sast/coverity-standard.json"),
            exit_for_file(results, "sast/coverity-standard.json"),
            "cov-analyze --all",
        ),
        tool_run(
            results,
            "coverity/compliance/cert",
            "coverity-cert",
            version(["/opt/coverity/bin/cov-analyze", "--version"]),
            status_for_file(results, "compliance/coverity-cert.json"),
            exit_for_file(results, "compliance/coverity-cert.json"),
            "cov-analyze --coding-standard-config CERT C",
        ),
        tool_run(
            results,
            "coverity/compliance/misra",
            "coverity-misra",
            version(["/opt/coverity/bin/cov-analyze", "--version"]),
            status_for_file(results, "compliance/coverity-misra.json"),
            exit_for_file(results, "compliance/coverity-misra.json"),
            "cov-analyze --coding-standard-config MISRA C 2012",
        ),
        tool_run(
            results,
            "gitleaks",
            "gitleaks",
            version(["gitleaks", "version"]),
            status_for_file(results, "sast/gitleaks.json"),
            exit_for_file(results, "sast/gitleaks.json"),
            "gitleaks detect --no-git",
        ),
        tool_run(
            results,
            "syft",
            "syft",
            version(["syft", "version"]),
            status_for_file(results, "sca/sbom-source.cyclonedx.json"),
            exit_for_file(results, "sca/sbom-source.cyclonedx.json"),
            "syft source CycloneDX SBOM",
        ),
        tool_run(
            results,
            "vendor-manifest",
            "vendor-manifest",
            "curated",
            status_for_file(results, "sca/vendor-manifest.cdx.json"),
            exit_for_file(results, "sca/vendor-manifest.cdx.json"),
            "curated vendor manifest copied from project contract",
        ),
        tool_run(
            results,
            "grype/source",
            "grype",
            version(["grype", "version"]),
            status_for_file(results, "sca/grype-source.json"),
            exit_for_file(results, "sca/grype-source.json"),
            "grype source SBOM scan",
        ),
        tool_run(
            results,
            "grype/vendor",
            "grype",
            version(["grype", "version"]),
            status_for_file(results, "sca/grype-vendor-manifest.json"),
            exit_for_file(results, "sca/grype-vendor-manifest.json"),
            "grype vendor manifest scan",
        ),
        tool_run(
            results,
            "grype/emba",
            "grype",
            version(["grype", "version"]),
            status_for_file(results, "sca/grype-emba.json"),
            exit_for_file(results, "sca/grype-emba.json"),
            "grype EMBA/runtime SBOM scan",
        ),
        tool_run(
            results,
            "owaspdc",
            "owaspdc",
            version(["/opt/dependency-check/bin/dependency-check.sh", "--version"]),
            status_for_file(results, "sca/owaspdc.json"),
            exit_for_file(results, "sca/owaspdc.json"),
            "dependency-check.sh --format JSON --noupdate",
        ),
        tool_run(
            results,
            "libfuzzer",
            "libfuzzer",
            version(["clang", "--version"]),
            status_for_dir(results, "fuzzing/libfuzzer"),
            exit_for_dir(results, "fuzzing/libfuzzer"),
            "project fuzzing hook",
        ),
        tool_run(
            results,
            "emba/sbom",
            "emba",
            "unknown",
            status_for_file(results, "emba/SBOM/EMBA_cyclonedx_sbom.json"),
            emba_exit,
            "EMBA CycloneDX SBOM generation",
        ),
        tool_run(
            results,
            "emba/vex",
            "emba",
            "unknown",
            status_for_file(results, "emba/SBOM/EMBA_cyclonedx_vex_sbom.json"),
            emba_exit,
            "EMBA CycloneDX VEX SBOM generation",
        ),
        tool_run(
            results,
            "emba/f50",
            "emba",
            "unknown",
            "success"
            if any(
                (results / p).is_file()
                for p in [
                    "emba/f50_base_aggregator.txt",
                    "emba/f50_base_aggregator.csv",
                    "emba/csv_logs/f50_base_aggregator.csv",
                ]
            )
            else "skipped",
            emba_exit,
            "EMBA full-scan f50 base aggregator",
        ),
        tool_run(
            results,
            "checksec",
            "checksec",
            version(["checksec", "--version"]),
            status_for_file(results, "hardening/checksec.json"),
            exit_for_file(results, "hardening/checksec.json"),
            f"checksec --file={hardening_artifact}",
        ),
    ]

    return {"tool_runs": runs}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", required=True, help="Snapshot root containing raw/results")
    parser.add_argument("--dest", default="", help="Final artifact store path")
    parser.add_argument("--project", default="")
    parser.add_argument("--build", default="")
    parser.add_argument("--execution-type", default="")
    args = parser.parse_args()

    snapshot = Path(args.snapshot).resolve()
    dest = Path(args.dest).resolve() if args.dest else snapshot
    results = snapshot / "raw" / "results"
    metadata_dir = snapshot / "metadata"
    metadata_dir.mkdir(parents=True, exist_ok=True)

    original_build = read_json(metadata_dir / "build.json")

    project = first_non_empty(args.project, env("PROJECT_NAME"), original_build.get("project", "unknown"))
    build_id = first_non_empty(args.build, env("BUILD_NUMBER"), original_build.get("jenkins_build_number", "manual"))
    execution_type = first_non_empty(args.execution_type, env("EXECUTION_TYPE"), original_build.get("execution_type", "ci_pipeline"))

    git_branch = first_non_empty(env("BRANCH_NAME"), run_text(["git", "rev-parse", "--abbrev-ref", "HEAD"]))
    if git_branch == "HEAD":
        git_branch = ""
    git_branch = first_non_empty(git_branch, env("GIT_BRANCH"), original_build.get("git_branch", "UNKNOWN"))

    git_commit = first_non_empty(env("GIT_COMMIT"), run_text(["git", "rev-parse", "HEAD"]), original_build.get("git_commit", "UNKNOWN"))
    repo_url = first_non_empty(env("PROJECT_REPO_URL"), run_text(["git", "config", "--get", "remote.origin.url"]), original_build.get("repo_url", ""))

    build_json = {
        "project": project,
        "project_db_name": first_non_empty(env("PROJECT_DB_NAME"), original_build.get("project_db_name", project)),
        "repo_url": repo_url,
        "language": first_non_empty(env("PROJECT_LANGUAGE"), original_build.get("language", "unknown")),
        "platform_type": first_non_empty(env("PROJECT_PLATFORM_TYPE"), original_build.get("platform_type", "unknown")),
        "execution_type": execution_type,
        "jenkins_build_number": build_id,
        "jenkins_build_url": env("BUILD_URL", original_build.get("jenkins_build_url", "")),
        "job_name": env("JOB_NAME", original_build.get("job_name", "")),
        "git_branch": git_branch,
        "git_commit": git_commit,
        "workspace": env("WORKSPACE", original_build.get("workspace", "")),
        "persisted_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "artifact_store": str(dest),
        "raw_results_path": str(dest / "raw" / "results"),
        "artifact_store_version": "1.0",
        "notes": "Raw DevSecOps results snapshot persisted for ETL and Jenkins evidence.",
    }
    write_json(metadata_dir / "build.json", build_json)

    source_required = bool_env("SOURCE_SBOM_REQUIRED", True)
    vendor_required = bool_env("VENDOR_MANIFEST_REQUIRED", False)

    inventories: List[Dict[str, Any]] = []
    add_inventory(
        inventories,
        snapshot,
        dest,
        "source_sbom",
        "syft-source-sbom",
        "sca/sbom-source.cyclonedx.json",
        "source_sbom",
        "SYFT_SBOM",
        "source_or_build_inventory",
        "SCA_SOURCE_SBOM",
        source_required,
    )
    add_inventory(
        inventories,
        snapshot,
        dest,
        "vendor_manifest",
        "curated-vendor-manifest",
        "sca/vendor-manifest.cdx.json",
        "vendor_manifest",
        "VENDOR_MANIFEST",
        "curated_dependency_inventory",
        "SCA_VENDOR_MANIFEST",
        vendor_required,
    )
    add_inventory(
        inventories,
        snapshot,
        dest,
        "emba_sbom",
        "emba-runtime-sbom",
        "emba/SBOM/EMBA_cyclonedx_sbom.json",
        "emba_sbom",
        "EMBA_SBOM",
        "runtime_rootfs_inventory",
        "SCA_FIRMWARE_SBOM",
        False,
    )

    write_json(
        metadata_dir / "inventories.json",
        {
            "project": project,
            "build_id": build_id,
            "inventories": inventories,
        },
    )

    write_json(metadata_dir / "tool-runs.json", build_tool_runs(results))

    inventory_relative_paths = {
        "source_sbom": "sca/sbom-source.cyclonedx.json",
        "vendor_manifest": "sca/vendor-manifest.cdx.json",
        "emba_sbom": "emba/SBOM/EMBA_cyclonedx_sbom.json",
    }
    required_missing = []
    for inventory in inventories:
        relative = inventory_relative_paths[inventory["id"]]
        if inventory["required"] and not (snapshot / "raw" / "results" / relative).is_file():
            required_missing.append(inventory["logical_name"])

    if required_missing:
        raise SystemExit(f"Required inventories missing: {', '.join(required_missing)}")

    for relative in [
        "sast/gitleaks.json",
        "sast/coverity-standard.json",
        "sast/coverity.json",
        "compliance/coverity-cert.json",
        "compliance/coverity-misra.json",
        "sca/grype-db-status.json",
        "sca/grype-source.json",
        "sca/grype-vendor-manifest.json",
        "sca/grype-emba.json",
        "sca/owaspdc.json",
        "hardening/checksec.json",
    ]:
        validate_json_if_present(results / relative)

    for relative in [
        "sca/sbom-source.cyclonedx.json",
        "sca/vendor-manifest.cdx.json",
        "emba/SBOM/EMBA_cyclonedx_sbom.json",
    ]:
        validate_cyclonedx_if_present(results / relative)

    for path in [
        metadata_dir / "build.json",
        metadata_dir / "inventories.json",
        metadata_dir / "tool-runs.json",
    ]:
        validate_json_if_present(path)

    print(f"[OK] ETL metadata generated under {metadata_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
