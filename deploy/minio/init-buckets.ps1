# Run once after deploying MinIO to create buckets and enable versioning.
# Requires the MinIO Client (mc.exe) to be installed and on PATH.
#
# Usage:
#   .\init-buckets.ps1 -Endpoint "http://<truenas-ip>:9000"

param(
    [string]$Endpoint = "http://localhost:9000"
)

$ErrorActionPreference = "Stop"

Write-Host "Configuring MinIO alias at $Endpoint ..."
mc alias set voxl $Endpoint minioadmin minioadmin

Write-Host "Creating buckets ..."
mc mb voxl/voxl-palettes --ignore-existing
mc mb voxl/voxl-tiles --ignore-existing

Write-Host "Enabling versioning ..."
mc version enable voxl/voxl-palettes
mc version enable voxl/voxl-tiles

Write-Host "Setting anonymous read/write policy (LAN-only) ..."
mc anonymous set public voxl/voxl-palettes
mc anonymous set public voxl/voxl-tiles

Write-Host "Done. Buckets are ready for the VOXL editor." -ForegroundColor Green
