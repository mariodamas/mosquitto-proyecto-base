#!/bin/sh
# setup_owasp_depcheck.sh
# -----------------------
# Helper script to install/setup OWASP Dependency Check for the lab environment.
# Supports Windows (WSL/PowerShell), Linux, and macOS.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPCHECK_VERSION="${DEPCHECK_VERSION:-8.4.2}"

# Platform detection
OS_TYPE=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE="${ID}"
elif [ "$(uname -s)" = "Darwin" ]; then
    OS_TYPE="macos"
else
    OS_TYPE="linux"
fi

echo "=== OWASP Dependency Check Setup ==="
echo "Version: ${DEPCHECK_VERSION}"
echo "Detected OS: ${OS_TYPE}"
echo ""

# Check if already installed
if command -v dependency-check.sh >/dev/null 2>&1 || \
   command -v dependency-check >/dev/null 2>&1; then
    echo "✓ Dependency Check already installed"
    dependency-check.sh --version 2>/dev/null || dependency-check --version 2>/dev/null || true
    echo ""
    echo "To update database:"
    echo "  dependency-check.sh --updateonly"
    exit 0
fi

# Check Java availability
if ! command -v java >/dev/null 2>&1; then
    echo "ERROR: Java 8 or higher required but not found." >&2
    echo "" >&2
    echo "Install Java:" >&2
    if [ "${OS_TYPE}" = "ubuntu" ] || [ "${OS_TYPE}" = "debian" ]; then
        echo "  sudo apt-get install default-jre" >&2
    elif [ "${OS_TYPE}" = "fedora" ] || [ "${OS_TYPE}" = "rhel" ]; then
        echo "  sudo dnf install java-11-openjdk" >&2
    elif [ "${OS_TYPE}" = "macos" ]; then
        echo "  brew install openjdk@11" >&2
    else
        echo "  Download from: https://www.oracle.com/java/technologies/downloads/" >&2
    fi
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | grep "version" | awk -F'"' '{print $2}' | cut -d'.' -f1)
echo "✓ Java found (version ${JAVA_VERSION})"

# Download and install
INSTALL_DIR="${HOME}/.local/share/owasp-depcheck"
mkdir -p "${INSTALL_DIR}"

echo ""
echo "Downloading Dependency Check ${DEPCHECK_VERSION}..."
DOWNLOAD_URL="https://github.com/jeremylong/DependencyCheck_Doc/releases/download/v${DEPCHECK_VERSION}/dependency-check-${DEPCHECK_VERSION}-release.zip"

# Use curl or wget
if command -v curl >/dev/null 2>&1; then
    curl -L -o "${INSTALL_DIR}/depcheck.zip" "${DOWNLOAD_URL}"
elif command -v wget >/dev/null 2>&1; then
    wget -O "${INSTALL_DIR}/depcheck.zip" "${DOWNLOAD_URL}"
else
    echo "ERROR: curl or wget required to download." >&2
    exit 1
fi

echo "Extracting..."
if command -v unzip >/dev/null 2>&1; then
    unzip -q -o -d "${INSTALL_DIR}" "${INSTALL_DIR}/depcheck.zip"
else
    echo "ERROR: unzip required." >&2
    exit 1
fi

# Create symlink in /usr/local/bin or add to PATH
DEPCHECK_BIN="${INSTALL_DIR}/dependency-check/bin/dependency-check.sh"

if [ -w "/usr/local/bin" ]; then
    echo "Creating symlink in /usr/local/bin..."
    ln -sf "${DEPCHECK_BIN}" /usr/local/bin/dependency-check.sh
    echo "✓ dependency-check.sh available globally"
else
    echo ""
    echo "To add to PATH, add this line to ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"${INSTALL_DIR}/dependency-check/bin:\$PATH\""
    echo ""
    echo "Or create a symlink manually:"
    echo "  sudo ln -s \"${DEPCHECK_BIN}\" /usr/local/bin/dependency-check.sh"
fi

# Cleanup
rm "${INSTALL_DIR}/depcheck.zip"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "First run will download NVD database (~1GB, 5-15 minutes):"
echo "  dependency-check.sh --updateonly"
echo ""
echo "To verify installation:"
echo "  dependency-check.sh --version"
echo ""
echo "To run lab validation:"
echo "  ./.lab/validate/06_validate_sca_owasp_depcheck.sh"
