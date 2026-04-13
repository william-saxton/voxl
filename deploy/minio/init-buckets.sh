#!/usr/bin/env bash
# Run once after deploying MinIO to create buckets and enable versioning.
# Requires the MinIO Client (mc) to be installed.
#
# Usage:
#   MINIO_ENDPOINT=http://<truenas-ip>:9000 ./init-buckets.sh

set -euo pipefail

MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"

echo "Configuring MinIO alias at ${MINIO_ENDPOINT} ..."
mc alias set voxl "${MINIO_ENDPOINT}" minioadmin minioadmin

echo "Creating buckets ..."
mc mb voxl/voxl-palettes --ignore-existing
mc mb voxl/voxl-tiles    --ignore-existing

echo "Enabling versioning ..."
mc version enable voxl/voxl-palettes
mc version enable voxl/voxl-tiles

echo "Setting anonymous read/write policy (LAN-only) ..."
mc anonymous set public voxl/voxl-palettes
mc anonymous set public voxl/voxl-tiles

echo "Done. Buckets are ready for the VOXL editor."
