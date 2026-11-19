#!/usr/bin/env bash
# Build a Docker image from a folder and push it to your ECR repo.
# Usage: ./push.sh <folder-with-Dockerfile> <tag>
#   e.g. ./push.sh examples/python-hello python-hello
# The Dockerfile can COPY the wrapper with:  COPY --from=wrapper exp-wrapper.sh /usr/local/bin/exp-wrapper
set -euo pipefail

DIR="${1:?usage: ./push.sh <folder> <tag>}"
TAG="${2:?usage: ./push.sh <folder> <tag>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

IMAGE="${ECR_REPO}:${TAG}"
aws ecr describe-repositories --repository-names "${PREFIX}-images" >/dev/null 2>&1 \
  || { echo "error: ECR repo ${PREFIX}-images not found; is terraform/foundation applied?" >&2; exit 1; }

aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR_REGISTRY"
# linux/amd64 = what the Batch instances (x86 instance types) run, even if your laptop is ARM.
docker build --platform linux/amd64 --build-context wrapper="$HERE/platform" -t "$IMAGE" "$DIR"
docker push "$IMAGE"
echo "pushed: $IMAGE"
