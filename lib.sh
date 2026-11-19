# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this
# Shared settings for run.sh, push.sh, status.sh, teardown.sh. Source it; do not execute it.
#
# This is the ONE place in the scripts that knows how resources are named. The names must
# match the Terraform defaults (variable "name" and "region", and the resource names in
# terraform/foundation). `require_platform` fails with a clear message if they ever drift.

# Optional per-user settings (PREFIX, AWS_PROFILE, ...). Git-ignored: copy
# config.local.sh.example to config.local.sh. Nothing personal belongs in tracked files.
if [ -f "$(dirname "${BASH_SOURCE[0]}")/config.local.sh" ]; then
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/config.local.sh"
fi

PREFIX="${PREFIX:-exp}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-north-1}"
REGION="$AWS_DEFAULT_REGION"
ACCOUNT="${ACCOUNT:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)}"
if [ -z "$ACCOUNT" ]; then
  echo "error: could not determine the AWS account. Are your AWS credentials configured and valid?" >&2
  exit 1
fi

STATE_BUCKET="${PREFIX}-tfstate-${ACCOUNT}-${REGION}"
RESULTS_BUCKET="${PREFIX}-results-${ACCOUNT}-${REGION}"
ECR_REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
ECR_REPO="${ECR_REGISTRY}/${PREFIX}-images"
JOB_ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${PREFIX}-batch-job"
LOG_GROUP="/${PREFIX}/jobs"

# Fail early, with an explanation, if the foundation layer is not deployed (or names drifted).
require_platform() {
  if ! aws s3api head-bucket --bucket "$RESULTS_BUCKET" >/dev/null 2>&1; then
    echo "error: bucket s3://${RESULTS_BUCKET} not found in ${REGION}." >&2
    echo "       Is terraform/foundation applied? Do PREFIX/AWS_DEFAULT_REGION match the Terraform variables?" >&2
    return 1
  fi
}
