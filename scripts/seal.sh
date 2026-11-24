#!/usr/bin/env bash
# Seal PAYMENT_API_KEY for each environment using the LOCAL public cert (works offline).
# Only the encrypted SealedSecret is written into the repo.
#   ./scripts/seal.sh                 # random token per env
#   PAYMENT_API_KEY_PROD=newvalue ./scripts/seal.sh prod   # rotate one env
set -euo pipefail
cd "$(dirname "$0")/.."
command -v kubeseal >/dev/null || { echo "install kubeseal first"; exit 1; }
CERT=".secrets/sealed-secrets.crt"
[ -f "$CERT" ] || { echo "$CERT missing: run ./bootstrap.sh first (it generates the key pair)"; exit 1; }
ENVS=("${@:-dev staging prod}")
[ $# -eq 0 ] && ENVS=(dev staging prod)
for env in "${ENVS[@]}"; do
  var="PAYMENT_API_KEY_$(echo "$env" | tr a-z A-Z)"
  token="${!var:-$(openssl rand -hex 12)}"
  out="services/storefront/overlays/${env}/sealed-secret.yaml"
  kubeseal --cert "$CERT" --format yaml <<YAML > "$out"
apiVersion: v1
kind: Secret
metadata:
  name: storefront-secrets
  namespace: shop-${env}
type: Opaque
stringData:
  PAYMENT_API_KEY: "${token}"
YAML
  echo "sealed ${env} -> ${out}"
done
echo "Review, then: git add -A && git commit -m 'rotate secrets' && git push"
