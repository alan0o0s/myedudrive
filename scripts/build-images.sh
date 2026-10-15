#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME to your Docker Hub username}"
: "${NEXTCLOUD_VERSION:?Set NEXTCLOUD_VERSION to the exact installed server version, for example 35.0.1}"
IMAGE_TAG="${IMAGE_TAG:-v1.1.2}"

if [[ ! "${NEXTCLOUD_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "NEXTCLOUD_VERSION must be an exact x.y.z version, not 'latest' or a moving tag." >&2
  exit 1
fi

docker build \
  --build-arg "NEXTCLOUD_BASE_IMAGE=nextcloud:${NEXTCLOUD_VERSION}-apache" \
  --file "${ROOT_DIR}/images/nextcloud/Dockerfile" \
  --tag "${DOCKERHUB_USERNAME}/myedudrive-server:${IMAGE_TAG}" \
  "${ROOT_DIR}"

echo "Built unified application image:"
echo "  ${DOCKERHUB_USERNAME}/myedudrive-server:${IMAGE_TAG}"
echo "Push only after reviewing the images: docker push <image-tag>"
