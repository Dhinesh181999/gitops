#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FROM="${1:?usage: $0 <from-env> <to-env>}"
TO="${2:?usage: $0 <from-env> <to-env>}"
case "$FROM:$TO" in
  dev:staging|staging:prod) ;;
  *) echo "promotion must be dev -> staging or staging -> prod" >&2; exit 1 ;;
esac

SOURCE="services/demo-api/overlays/${FROM}/kustomization.yaml"
TARGET="services/demo-api/overlays/${TO}/kustomization.yaml"
TAG="$(yq '.images[0].newTag' "$SOURCE")"
yq -i ".images[0].newTag = \"${TAG}\"" "$TARGET"
echo "Promoted ${TAG}: ${FROM} -> ${TO}. Review the diff and commit it."
git --no-pager diff -- "$TARGET"
