#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required." >&2
  exit 1
fi
if ! kubectl config current-context >/dev/null 2>&1; then
  echo "No kubectl context is active; cannot run live-cluster checks." >&2
  exit 1
fi

kubectl -n myedudrive get pods,svc,pvc
kubectl -n myedudrive rollout status statefulset/mariadb --timeout=5m
kubectl -n myedudrive rollout status statefulset/redis --timeout=5m
kubectl -n myedudrive rollout status deployment/nextcloud --timeout=5m
kubectl -n myedudrive exec statefulset/mariadb -- healthcheck.sh --connect --innodb_initialized
kubectl -n myedudrive exec statefulset/redis -- redis-cli ping
kubectl -n myedudrive exec deployment/nextcloud -- php occ status
SKELETON_DIRECTORY="$(kubectl -n myedudrive exec deployment/nextcloud -- php occ config:system:get skeletondirectory --default-value=__MYEDUDRIVE_UNSET__)"
if [[ -n "${SKELETON_DIRECTORY}" ]]; then
  echo "FAIL: skeletondirectory is not empty; new users may receive bundled sample files." >&2
  exit 1
fi
echo "PASS: Nextcloud skeleton provisioning is disabled for new users."
if kubectl -n myedudrive exec deployment/nextcloud -- php occ app:list --enabled | grep -q 'firstrunwizard'; then
  echo "FAIL: firstrunwizard is enabled; new accounts may see onboarding dialogs." >&2
  exit 1
fi
echo "PASS: firstrunwizard is disabled for new accounts."
kubectl -n myedudrive get cronjob nextcloud-cron
kubectl -n myedudrive get hpa
