#!/bin/sh
# build_artifact.sh
# -----------------
# Build the reproducible-build Docker image and extract the Mosquitto ELF
# artifact to .lab/docker/output/mosquitto for later binary analysis.
#
# This script does NOT install Docker. Docker must already be available on
# the host. It does NOT orchestrate Jenkins; it is a stand-alone helper.
#
# Usage (run from any directory):
#   sh .lab/docker/build_artifact.sh
#
# The resulting binary is written to:
#   <repo_root>/.lab/docker/output/mosquitto

set -eu

# Resolve repo root regardless of where the script is called from.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd -P)"
OUTPUT_DIR="$SCRIPT_DIR/output"
IMAGE_TAG="mosquitto-lab-build:v2.0.18"

mkdir -p "$OUTPUT_DIR"

echo "[build_artifact] repo root : $REPO_ROOT"
echo "[build_artifact] image     : $IMAGE_TAG"
echo "[build_artifact] output dir: $OUTPUT_DIR"

# Build the Docker image from the repository root so COPY . /src works.
docker build \
    --file "$SCRIPT_DIR/Dockerfile.build" \
    --tag "$IMAGE_TAG" \
    --progress plain \
    "$REPO_ROOT"

# Extract the artifact from the image without running a container.
# `docker create` creates a stopped container from the image so we can
# copy from its filesystem, then `docker rm` cleans it up.
CONTAINER_ID="$(docker create "$IMAGE_TAG")"
docker cp "${CONTAINER_ID}:/output/mosquitto" "$OUTPUT_DIR/mosquitto"
docker rm "$CONTAINER_ID" > /dev/null

# Confirm the artifact exists and print a brief summary.
if [ -f "$OUTPUT_DIR/mosquitto" ]; then
    echo "[build_artifact] artifact : $OUTPUT_DIR/mosquitto"
    ls -lh "$OUTPUT_DIR/mosquitto"
    file "$OUTPUT_DIR/mosquitto" || true
else
    echo "[build_artifact] ERROR: artifact not found at $OUTPUT_DIR/mosquitto" >&2
    exit 1
fi
