#!/usr/bin/env bash
# Promotion = a Git diff. Copies the image tag from one overlay to the next.
#   ./scripts/promote.sh dev staging     # then open a PR / commit
#   ./scripts/promote.sh staging prod
set -euo pipefail
cd "$(dirname "$0")/.."
FROM="${1:?from-env}"; TO="${2:?to-env}"
TAG="$(yq '.images[0].newTag' "services/storefront/overlays/${FROM}/kustomization.yaml")"
yq -i ".images[0].newTag = \"${TAG}\"" "services/storefront/overlays/${TO}/kustomization.yaml"
echo "Promoted ${TAG}: ${FROM} -> ${TO}"; git --no-pager diff --stat
