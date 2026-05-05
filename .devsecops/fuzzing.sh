#!/usr/bin/env bash
set -euo pipefail

PROJECT_CONFIG="${PROJECT_CONFIG:-.devsecops/project.env}"
if [ -f "${PROJECT_CONFIG}" ]; then
  # shellcheck disable=SC1090
  source "${PROJECT_CONFIG}"
fi

BUILD_SCRIPT="${BUILD_SCRIPT:-.devsecops/build.sh}"
FUZZING_CAMPAIGN_TIME="${FUZZING_CAMPAIGN_TIME:-300}"
ALLOW_FUZZING_FAILURES="${ALLOW_FUZZING_FAILURES:-true}"
PROJECT_NAME="${PROJECT_NAME:-project}"
FUZZING_PERSISTENT_CORPUS_NAME="${FUZZING_PERSISTENT_CORPUS_NAME:-${PROJECT_NAME}}"
export ALLOW_FUZZING_FAILURES

if ! [[ "${FUZZING_CAMPAIGN_TIME}" =~ ^[0-9]+$ ]] || [ "${FUZZING_CAMPAIGN_TIME}" -lt 1 ]; then
  echo "ERROR: FUZZING_CAMPAIGN_TIME must be a positive integer number of seconds" >&2
  exit 1
fi

test -f "${BUILD_SCRIPT}"
test -d .lab/fuzzing

bash "${BUILD_SCRIPT}" build
rm -rf .lab/fuzzing/findings

(
  cd .lab/fuzzing
  python3 corpus/generate_corpus.py
  bash ./build_libfuzzer.sh

  FUZZING_PERSISTENT_CORPUS_DIR="/opt/devsecops-lab/fuzzing-corpus/${FUZZING_PERSISTENT_CORPUS_NAME}" \
  ALLOW_FUZZING_FAILURES="${ALLOW_FUZZING_FAILURES}" \
  CAMPAIGN_TIME="${FUZZING_CAMPAIGN_TIME}" \
  bash ./run_campaigns.sh libfuzzer
)

mkdir -p results/fuzzing
if [ -d .lab/fuzzing/findings ]; then
  cp -a .lab/fuzzing/findings/. results/fuzzing/
fi

if [ -d .lab/fuzzing/build ]; then
  mkdir -p results/fuzzing/build
  cp -a .lab/fuzzing/build/. results/fuzzing/build/
fi

python3 - <<'PY'
import os
import sys
from pathlib import Path

allow_failures = os.environ.get("ALLOW_FUZZING_FAILURES", "true").lower() == "true"
root = Path("results/fuzzing/libfuzzer")

if not root.exists():
    print("[WARN] No libFuzzer results were produced")
    sys.exit(0)

infra_errors = []
harness_failures = []

for harness_dir in sorted(p for p in root.iterdir() if p.is_dir()):
    name = harness_dir.name
    log = harness_dir / "run.log"
    exit_code = harness_dir / "exit_code.txt"
    metadata = harness_dir / "metadata.txt"
    corpus = harness_dir / "corpus"

    if not log.is_file() or log.stat().st_size == 0:
        infra_errors.append(f"{name}: run.log missing or empty")
    if not exit_code.is_file():
        infra_errors.append(f"{name}: exit_code.txt missing")
    if not metadata.is_file():
        infra_errors.append(f"{name}: metadata.txt missing")
    if not corpus.is_dir() or not any(corpus.iterdir()):
        infra_errors.append(f"{name}: corpus missing or empty")

    if exit_code.is_file():
        code = exit_code.read_text(encoding="utf-8", errors="replace").strip()
        print(f"[OK] {name}: exit_code={code} log={log.stat().st_size if log.exists() else 0}B")
        if code != "0":
            harness_failures.append(f"{name}: exit_code={code}")

if infra_errors:
    for error in infra_errors:
        print(f"[FAIL] {error}", file=sys.stderr)
    sys.exit(1)

if harness_failures and not allow_failures:
    for failure in harness_failures:
        print(f"[FAIL] {failure}", file=sys.stderr)
    sys.exit(1)
PY
