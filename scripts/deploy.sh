#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/secrets.env"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required." >&2
  exit 1
fi
if ! kubectl config current-context >/dev/null 2>&1; then
  echo "No kubectl context is active. Start Minikube and select its context first." >&2
  exit 1
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy secrets.env.example to secrets.env and set strong passwords." >&2
  exit 1
fi

kubectl apply -f "${ROOT_DIR}/k8s/base/namespace.yaml"
kubectl -n myedudrive create secret generic myedudrive-secrets \
  --from-env-file="${ENV_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k "${ROOT_DIR}/k8s/overlays/dockerhub"
kubectl -n myedudrive rollout status statefulset/mariadb --timeout=30m
kubectl -n myedudrive rollout status statefulset/redis --timeout=5m
kubectl -n myedudrive rollout status deployment/nextcloud --timeout=30m
# Keep the existing external NodePort service, now pointed straight at
# Nextcloud, and remove only the obsolete reverse-proxy workload.
kubectl -n myedudrive delete deployment myedudrive-nginx --ignore-not-found
kubectl -n myedudrive delete configmap nginx-config --ignore-not-found
kubectl -n myedudrive exec deployment/nextcloud -- /usr/local/bin/myedudrive-apply-branding
kubectl -n myedudrive get pods,svc,pvc
