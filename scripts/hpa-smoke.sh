#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="myedudrive"
MAX_WAIT_SECONDS="${1:-240}"
LABEL_SELECTOR="app.kubernetes.io/name=nextcloud"
PID_FILE="/tmp/myedudrive-hpa-smoke.pid"
REACHED_MAX=0

if ! [[ "${MAX_WAIT_SECONDS}" =~ ^[0-9]+$ ]] || (( MAX_WAIT_SECONDS < 30 )); then
  echo "Usage: $0 [timeout-seconds, at least 30]" >&2
  exit 2
fi
if ! kubectl -n "${NAMESPACE}" get hpa nextcloud >/dev/null 2>&1; then
  echo "HPA not found. Deploy the scaling overlay first." >&2
  exit 1
fi
if ! kubectl top pods -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" >/dev/null 2>&1; then
  echo "Metrics API is unavailable. Check the metrics-server add-on and kubectl top." >&2
  exit 1
fi

cleanup() {
  while read -r pod; do
    [[ -n "${pod}" ]] || continue
    kubectl -n "${NAMESPACE}" exec "${pod}" -- sh -c \
      'if [ -f /tmp/myedudrive-hpa-smoke.pid ]; then kill "$(cat /tmp/myedudrive-hpa-smoke.pid)" 2>/dev/null || true; rm -f /tmp/myedudrive-hpa-smoke.pid; fi' \
      >/dev/null 2>&1 || true
  done < <(kubectl -n "${NAMESPACE}" get pods -l "${LABEL_SELECTOR}" -o name 2>/dev/null)
}
trap cleanup EXIT
trap 'exit 130' INT TERM

start_workers() {
  while read -r pod phase; do
    [[ "${phase}" == "Running" ]] || continue
    kubectl -n "${NAMESPACE}" exec "${pod}" -- sh -c \
      'if [ ! -f /tmp/myedudrive-hpa-smoke.pid ]; then nohup sh -c "while :; do :; done" >/dev/null 2>&1 & echo $! > /tmp/myedudrive-hpa-smoke.pid; fi' \
      >/dev/null 2>&1 || true
  done < <(kubectl -n "${NAMESPACE}" get pods -l "${LABEL_SELECTOR}" \
    -o custom-columns=NAME:.metadata.name,PHASE:.status.phase --no-headers 2>/dev/null)
}

DEADLINE=$((SECONDS + MAX_WAIT_SECONDS))
while (( SECONDS < DEADLINE )); do
  start_workers
  HPA_STATE="$(kubectl -n "${NAMESPACE}" get hpa nextcloud \
    -o jsonpath='{.status.desiredReplicas} {.status.currentReplicas} {.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)"
  DESIRED=""; READY=""; CPU=""
  read -r DESIRED READY CPU <<<"${HPA_STATE}" || true
  printf 'HPA: desired=%s current=%s CPU=%s%%\n' "${DESIRED:-?}" "${READY:-?}" "${CPU:-?}"
  if [[ "${DESIRED:-0}" =~ ^[0-9]+$ ]] && (( DESIRED >= 10 )); then
    READY_DEPLOYMENT="$(kubectl -n "${NAMESPACE}" get deployment nextcloud -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    if [[ "${READY_DEPLOYMENT:-0}" =~ ^[0-9]+$ ]] && (( READY_DEPLOYMENT >= 10 )); then
      REACHED_MAX=1
      break
    fi
  fi
  sleep 10
done

if (( REACHED_MAX )); then
  echo "PASS: HPA reached 10 ready MyEduDrive replicas. CPU workers will now stop."
else
  echo "FAIL: HPA did not reach 10 ready replicas within ${MAX_WAIT_SECONDS}s." >&2
  exit 1
fi
