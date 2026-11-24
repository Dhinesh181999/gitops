#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CERT=".secrets/sealed-secrets.crt"
[ -f "$CERT" ] || { echo "$CERT missing; run ./bootstrap.sh first" >&2; exit 1; }
command -v kubeseal >/dev/null || { echo "kubeseal is required" >&2; exit 1; }
command -v yq >/dev/null || { echo "Mike Farah yq v4 is required" >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

if [ "$#" -eq 0 ]; then
  ENVS=(dev staging prod)
else
  ENVS=("$@")
fi

for env in "${ENVS[@]}"; do
  case "$env" in
    dev|staging|prod) ;;
    *) echo "unsupported environment: $env" >&2; exit 1 ;;
  esac

  var="DEMO_API_KEY_$(printf '%s' "$env" | tr '[:lower:]' '[:upper:]')"
  token="${!var:-$(openssl rand -hex 16)}"
  encoded="$(printf '%s' "$token" | base64 | tr -d '\n')"
  overlay="services/demo-api/overlays/${env}"
  output="${overlay}/sealed-secret.yaml"

  kubeseal --cert "$CERT" --scope strict --format yaml > "$output" <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: demo-api-secrets
  namespace: demo-${env}
type: Opaque
data:
  DEMO_API_KEY: "${encoded}"
YAML

  if ! yq '.resources[]' "${overlay}/kustomization.yaml" | grep -Fxq "sealed-secret.yaml"; then
    yq -i '.resources += ["sealed-secret.yaml"]' "${overlay}/kustomization.yaml"
  fi
  echo "Sealed secret generated for ${env}; only encrypted data is written to the repository."
done

echo "Review the encrypted manifests, then commit and push them to Git."
