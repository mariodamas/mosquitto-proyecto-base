#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-build}"
PROJECT_CONFIG="${PROJECT_CONFIG:-.devsecops/project.env}"

if [ -f "${PROJECT_CONFIG}" ]; then
  # shellcheck disable=SC1090
  source "${PROJECT_CONFIG}"
fi

PROJECT_NAME="${PROJECT_NAME:-project}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
CC_BIN="${CC:-clang}"
CXX_BIN="${CXX:-clang++}"
JOBS="${JOBS:-$(nproc)}"

cmake_configure() {
  local build_dir="$1"

  cmake -S . -B "${build_dir}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_C_COMPILER="${CC_BIN}" \
    -DCMAKE_CXX_COMPILER="${CXX_BIN}" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DDOCUMENTATION=OFF \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE" \
    -DCMAKE_EXE_LINKER_FLAGS="-pie -Wl,-z,relro,-z,now"
}

cmake_build() {
  local build_dir="$1"
  cmake --build "${build_dir}" --clean-first -j"${JOBS}"
}

run_build_action() {
  local action="$1"

  case "${action}" in
    build)
      cmake_configure build
      cmake_build build
      ;;
    codeql-configure)
      rm -rf build-codeql
      cmake_configure build-codeql
      ;;
    codeql-build)
      cmake_build build-codeql
      ;;
    coverity-configure)
      rm -rf build-coverity
      cmake_configure build-coverity
      ;;
    coverity-build)
      cmake_build build-coverity
      ;;
    *)
      return 1
      ;;
  esac
}

run_fuzzing() {
  local campaign_time="${FUZZING_CAMPAIGN_TIME:-300}"
  local allow_failures="${ALLOW_FUZZING_FAILURES:-true}"
  local corpus_name="${FUZZING_PERSISTENT_CORPUS_NAME:-${PROJECT_NAME}}"

  if ! [[ "${campaign_time}" =~ ^[0-9]+$ ]] || [ "${campaign_time}" -lt 1 ]; then
    echo "ERROR: FUZZING_CAMPAIGN_TIME must be a positive integer number of seconds" >&2
    return 1
  fi

  test -d .lab/fuzzing
  export ALLOW_FUZZING_FAILURES="${allow_failures}"

  run_build_action build
  rm -rf .lab/fuzzing/findings

  (
    cd .lab/fuzzing
    python3 corpus/generate_corpus.py
    bash ./build_libfuzzer.sh

    FUZZING_PERSISTENT_CORPUS_DIR="/opt/devsecops-lab/fuzzing-corpus/${corpus_name}" \
    ALLOW_FUZZING_FAILURES="${allow_failures}" \
    CAMPAIGN_TIME="${campaign_time}" \
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

for harness_dir in sorted(path for path in root.iterdir() if path.is_dir()):
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
}

run_firmware_package() {
  local build_artifact="${BUILD_ARTIFACT:?BUILD_ARTIFACT is required}"
  local target_name="${FIRMWARE_TARGET_NAME:-${PROJECT_NAME}-rootfs.tar.gz}"
  local binary_install_path="${FIRMWARE_BINARY_INSTALL_PATH:-usr/bin/$(basename "${build_artifact}")}"
  local firmware_version="${FIRMWARE_VERSION:-unknown}"
  local firmware_os_name="${FIRMWARE_OS_NAME:-${PROJECT_NAME} DevSecOps Lab Firmware}"
  local firmware_os_id="${FIRMWARE_OS_ID:-${PROJECT_NAME}-devsecops-lab}"
  local rootfs="${WORKSPACE:-$(pwd)}/build-rootfs/rootfs"

  rm -rf "${rootfs}"
  mkdir -p "${rootfs}" results/firmware

  install_file() {
    local src="$1"
    local dst_rel="$2"
    [ -e "${src}" ] || return 0
    mkdir -p "${rootfs}/$(dirname "${dst_rel}")"
    cp -a "${src}" "${rootfs}/${dst_rel}"
  }

  test -e "${build_artifact}"
  install_file "${build_artifact}" "${binary_install_path}"

  for item in ${FIRMWARE_CLIENT_ARTIFACTS:-}; do
    install_file "${item%%:*}" "${item#*:}"
  done

  mkdir -p \
    "${rootfs}/etc/init.d" \
    "${rootfs}/etc/mosquitto" \
    "${rootfs}/tmp" \
    "${rootfs}/var/lib/mosquitto" \
    "${rootfs}/var/log"

  cat > "${rootfs}/etc/os-release" <<EOF
NAME="${firmware_os_name}"
ID=${firmware_os_id}
VERSION_ID="${firmware_version}"
PRETTY_NAME="${firmware_os_name} ${firmware_version}"
EOF

  cat > "${rootfs}/etc/mosquitto/mosquitto.conf" <<'EOF'
pid_file /tmp/mosquitto.pid
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto.log
listener 1883
allow_anonymous true
EOF

  if [ -n "${FIRMWARE_INIT_COMMAND:-}" ]; then
    cat > "${rootfs}/etc/init.d/S50${PROJECT_NAME}" <<EOF
#!/bin/sh
case "\$1" in
  start)
    ${FIRMWARE_INIT_COMMAND}
    ;;
  stop)
    killall ${PROJECT_NAME} || true
    ;;
  *)
    echo "Usage: \$0 {start|stop}"
    exit 1
    ;;
esac
EOF
    chmod +x "${rootfs}/etc/init.d/S50${PROJECT_NAME}"
  fi

  if command -v ldd >/dev/null 2>&1 && [ -x "${build_artifact}" ]; then
    ldd "${build_artifact}" | tee "results/firmware/${PROJECT_NAME}-ldd.txt" || true

    ROOTFS="${rootfs}" BUILD_ARTIFACT="${build_artifact}" python3 - <<'PY'
import os
import re
import shutil
import subprocess
from pathlib import Path

rootfs = Path(os.environ["ROOTFS"])
binary = Path(os.environ["BUILD_ARTIFACT"])
manifest = Path("results/firmware/rootfs-copied-libraries.txt")

try:
    output = subprocess.check_output(["ldd", str(binary)], text=True, stderr=subprocess.STDOUT)
except Exception as exc:
    manifest.write_text(f"ldd failed: {exc}\n", encoding="utf-8")
    raise SystemExit(0)

paths = set()
for line in output.splitlines():
    for match in re.findall(r"(/[^\s]+)", line):
        candidate = Path(match)
        if candidate.exists():
            paths.add(candidate)

copied = []
for src in sorted(paths):
    dst = rootfs / src.relative_to("/")
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copy2(src, dst)
        copied.append(f"{src} -> {dst.relative_to(rootfs)}")
    except Exception as exc:
        copied.append(f"{src} -> COPY_FAILED: {exc}")

manifest.write_text("\n".join(copied) + "\n", encoding="utf-8")
print(f"[OK] copied {len(copied)} dynamic library entries")
PY
  fi

  mkdir -p "${rootfs}/var/lib/dpkg"
  if command -v dpkg-query >/dev/null 2>&1 && [ -n "${FIRMWARE_PACKAGE_STATUS_PACKAGES:-}" ]; then
    # shellcheck disable=SC2086
    dpkg-query -W -f='Package: ${binary:Package}\nVersion: ${Version}\nArchitecture: ${Architecture}\nStatus: install ok installed\n\n' \
      ${FIRMWARE_PACKAGE_STATUS_PACKAGES} > "${rootfs}/var/lib/dpkg/status" 2>/dev/null || true
  fi

  if [ ! -s "${rootfs}/var/lib/dpkg/status" ]; then
    cat > "${rootfs}/var/lib/dpkg/status" <<EOF
Package: ${PROJECT_NAME}-devsecops-lab
Version: ${firmware_version}
Architecture: amd64
Status: install ok installed
Description: Synthetic package metadata for DevSecOps lab firmware.
EOF
  fi

  find "${rootfs}" -maxdepth 5 -type f | sort > results/firmware/rootfs-file-list.txt

  local firmware_target="results/firmware/${target_name}"
  tar -C "${rootfs}" -czf "${firmware_target}" .
  test -s "${firmware_target}"
  printf '%s\n' "${firmware_target}" > results/firmware/firmware-target.txt
  echo "[OK] firmware package: ${firmware_target}"
}

if run_build_action "${ACTION}"; then
  exit 0
fi

case "${ACTION}" in
  fuzzing)
    run_fuzzing
    ;;
  package-firmware)
    run_firmware_package
    ;;
  *)
    echo "Usage: $0 {build|codeql-configure|codeql-build|coverity-configure|coverity-build|fuzzing|package-firmware}" >&2
    exit 2
    ;;
esac
