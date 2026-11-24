#!/usr/bin/env bash
# Fallback if you don't want to use GHCR: build and side-load into kind.
#   ./scripts/local-image.sh v1.0.0 <github-user>
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:?tag}"; USER_NAME="${2:?github-user}"
USER_NAME="${USER_NAME,,}"
docker build --build-arg APP_VERSION="$TAG" -t "ghcr.io/${USER_NAME}/storefront:${TAG}" app
kind load docker-image "ghcr.io/${USER_NAME}/storefront:${TAG}" --name delivery-lab
