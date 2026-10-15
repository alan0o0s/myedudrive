#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! kubectl config current-context >/dev/null 2>&1; then
  echo "No kubectl context is active. Start Minikube first." >&2
  exit 1
fi
if ! kubectl -n myedudrive get pvc nextcloud-data >/dev/null 2>&1; then
  echo "Deploy the base stack before enabling scaling." >&2
  exit 1
fi
kubectl apply -k "${ROOT_DIR}/k8s/overlays/scaling"
kubectl -n myedudrive get hpa nextcloud
