#!/usr/bin/env bash
# One-time setup: cluster, Argo CD, and the root app. After this, Git drives everything.
#   ./bootstrap.sh                      # default kind CNI
#   NETPOL_CNI=calico ./bootstrap.sh    # Calico, if your kind CNI doesn't enforce NetworkPolicy
#   GITHUB_TOKEN=... ./bootstrap.sh     # only if the repo is private
set -euo pipefail
cd "$(dirname "$0")"

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"
CALICO_VERSION="${CALICO_VERSION:-v3.28.2}"
CLUSTER_NAME="delivery-lab"
NETPOL_CNI="${NETPOL_CNI:-default}"
SECRETS_DIR=".secrets"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

log "Checking prerequisites"
for t in docker kind kubectl openssl git; do
  command -v "$t" >/dev/null || die "missing tool: $t"
done
docker info >/dev/null 2>&1 || die "docker daemon is not running"
if grep -rq "YOUR_GH_USER" --include='*.yaml' --include='*.yml' . 2>/dev/null; then
  die "repository placeholders found. Update GitHub URLs and image names before bootstrap."
fi
REPO_URL="${REPO_URL:-$(git remote get-url origin 2>/dev/null || true)}"
[ -n "$REPO_URL" ] || die "no git remote 'origin' (or set REPO_URL)"

log "Creating kind cluster '${CLUSTER_NAME}'"
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "cluster already exists, reusing"
else
  CFG="kind/cluster.yaml"; [ "$NETPOL_CNI" = "calico" ] && CFG="kind/cluster-calico.yaml"
  kind create cluster --config "$CFG"
fi
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

if [ "$NETPOL_CNI" = "calico" ]; then
  log "Installing Calico ${CALICO_VERSION}"
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
  kubectl -n kube-system rollout status ds/calico-node --timeout=300s
fi

log "Sealed Secrets key pair (persisted locally so rebuilds can still decrypt)"
mkdir -p "$SECRETS_DIR"
if [ ! -f "$SECRETS_DIR/sealed-secrets.key" ]; then
  openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout "$SECRETS_DIR/sealed-secrets.key" -out "$SECRETS_DIR/sealed-secrets.crt" \
    -subj "/CN=sealed-secrets/O=gitops-platform" 2>/dev/null
  chmod 600 "$SECRETS_DIR/sealed-secrets.key"
  echo "generated new key pair in $SECRETS_DIR/ (git-ignored)."
fi
kubectl -n kube-system create secret tls sealed-secrets-bootstrap-key \
  --cert="$SECRETS_DIR/sealed-secrets.crt" --key="$SECRETS_DIR/sealed-secrets.key" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kube-system label secret sealed-secrets-bootstrap-key \
  sealedsecrets.bitnami.com/sealed-secrets-key=active --overwrite

log "Installing Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
# poll Git every 30s instead of 3m so changes show up quickly
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"timeout.reconciliation":"30s"}}' >/dev/null
kubectl -n argocd rollout restart statefulset/argocd-application-controller >/dev/null
kubectl -n argocd rollout restart deploy/argocd-repo-server >/dev/null

if [ -n "${GITHUB_TOKEN:-}" ]; then
  log "Registering private repo credentials"
  kubectl -n argocd create secret generic repo-gitops --from-literal=type=git \
    --from-literal=url="$REPO_URL" --from-literal=username=git --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n argocd label secret repo-gitops argocd.argoproj.io/secret-type=repository --overwrite
fi

log "Binding Argo CD to the repo (root app-of-apps)"
kubectl apply -f platform/root-app.yaml

PASS="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
cat <<MSG

Bootstrap complete. Argo CD is now installing the platform from Git.

  UI:        kubectl -n argocd port-forward svc/argocd-server 8080:443   ->  https://localhost:8080
  login:     admin / ${PASS}
  Rollouts:  kubectl -n argo-rollouts port-forward svc/argo-rollouts-dashboard 3100:3100
  Apps:      http://demo-dev.localtest.me  http://demo-staging.localtest.me  http://demo-prod.localtest.me
Platform takes ~5-10 min (Prometheus is the slow one). Watch: kubectl -n argocd get applications -w
MSG
