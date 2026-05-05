#!/usr/bin/env bash
set -euo pipefail

PROJECT_CONFIG="${PROJECT_CONFIG:-.devsecops/project.env}"
if [ -f "${PROJECT_CONFIG}" ]; then
  # shellcheck disable=SC1090
  source "${PROJECT_CONFIG}"
fi

PROJECT_NAME="${PROJECT_NAME:-project}"
BUILD_ARTIFACT="${BUILD_ARTIFACT:?BUILD_ARTIFACT is required}"
FIRMWARE_TARGET_NAME="${FIRMWARE_TARGET_NAME:-${PROJECT_NAME}-rootfs.tar.gz}"
FIRMWARE_BINARY_INSTALL_PATH="${FIRMWARE_BINARY_INSTALL_PATH:-usr/bin/$(basename "${BUILD_ARTIFACT}")}"
FIRMWARE_VERSION="${FIRMWARE_VERSION:-unknown}"
FIRMWARE_OS_NAME="${FIRMWARE_OS_NAME:-${PROJECT_NAME} DevSecOps Lab Firmware}"
FIRMWARE_OS_ID="${FIRMWARE_OS_ID:-${PROJECT_NAME}-devsecops-lab}"

ROOTFS="${WORKSPACE:-$(pwd)}/build-rootfs/rootfs"
rm -rf "${ROOTFS}"
mkdir -p "${ROOTFS}"
mkdir -p results/firmware

install_file() {
  local src="$1"
  local dst_rel="$2"
  [ -e "${src}" ] || return 0
  mkdir -p "${ROOTFS}/$(dirname "${dst_rel}")"
  cp -a "${src}" "${ROOTFS}/${dst_rel}"
}

test -e "${BUILD_ARTIFACT}"
install_file "${BUILD_ARTIFACT}" "${FIRMWARE_BINARY_INSTALL_PATH}"

for item in ${FIRMWARE_CLIENT_ARTIFACTS:-}; do
  src="${item%%:*}"
  dst="${item#*:}"
  install_file "${src}" "${dst}"
done

mkdir -p \
  "${ROOTFS}/etc" \
  "${ROOTFS}/etc/init.d" \
  "${ROOTFS}/etc/mosquitto" \
  "${ROOTFS}/tmp" \
  "${ROOTFS}/var/lib/mosquitto" \
  "${ROOTFS}/var/log"

cat > "${ROOTFS}/etc/os-release" <<EOF
NAME="${FIRMWARE_OS_NAME}"
ID=${FIRMWARE_OS_ID}
VERSION_ID="${FIRMWARE_VERSION}"
PRETTY_NAME="${FIRMWARE_OS_NAME} ${FIRMWARE_VERSION}"
EOF

cat > "${ROOTFS}/etc/mosquitto/mosquitto.conf" <<'EOF'
pid_file /tmp/mosquitto.pid
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto.log
listener 1883
allow_anonymous true
EOF

if [ -n "${FIRMWARE_INIT_COMMAND:-}" ]; then
  cat > "${ROOTFS}/etc/init.d/S50${PROJECT_NAME}" <<EOF
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
  chmod +x "${ROOTFS}/etc/init.d/S50${PROJECT_NAME}"
fi

if command -v ldd >/dev/null 2>&1 && [ -x "${BUILD_ARTIFACT}" ]; then
  ldd "${BUILD_ARTIFACT}" | tee "results/firmware/${PROJECT_NAME}-ldd.txt" || true

  export ROOTFS BUILD_ARTIFACT
  python3 - <<'PY'
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

mkdir -p "${ROOTFS}/var/lib/dpkg"
if command -v dpkg-query >/dev/null 2>&1 && [ -n "${FIRMWARE_PACKAGE_STATUS_PACKAGES:-}" ]; then
  # shellcheck disable=SC2086
  dpkg-query -W -f='Package: ${binary:Package}\nVersion: ${Version}\nArchitecture: ${Architecture}\nStatus: install ok installed\n\n' \
    ${FIRMWARE_PACKAGE_STATUS_PACKAGES} > "${ROOTFS}/var/lib/dpkg/status" 2>/dev/null || true
fi

if [ ! -s "${ROOTFS}/var/lib/dpkg/status" ]; then
  cat > "${ROOTFS}/var/lib/dpkg/status" <<EOF
Package: ${PROJECT_NAME}-devsecops-lab
Version: ${FIRMWARE_VERSION}
Architecture: amd64
Status: install ok installed
Description: Synthetic package metadata for DevSecOps lab firmware.
EOF
fi

find "${ROOTFS}" -maxdepth 5 -type f | sort > results/firmware/rootfs-file-list.txt

FIRMWARE_TARGET="results/firmware/${FIRMWARE_TARGET_NAME}"
tar -C "${ROOTFS}" -czf "${FIRMWARE_TARGET}" .
test -s "${FIRMWARE_TARGET}"
printf '%s\n' "${FIRMWARE_TARGET}" > results/firmware/firmware-target.txt

echo "[OK] firmware package: ${FIRMWARE_TARGET}"
