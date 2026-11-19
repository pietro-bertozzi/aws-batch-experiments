#!/usr/bin/env bash
# Submit a job to the platform.
#
# Usage:
#   ./run.sh --image <tag> --experiment <name> [options] -- <command ...>
#
# Options:
#   --queue spot|ondemand   default: spot
#   --vcpus N               default: 2
#   --memory MiB            default: 4096
#   --run-id ID             default: timestamp. Reuse an existing ID to RESUME that run.
#   --sync-interval SEC     how often files are uploaded to S3 (default 120)
#
# Example:
#   ./run.sh --image python-hello --experiment hello --vcpus 1 --memory 1024 -- python main.py 30
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

IMAGE_TAG="" EXPERIMENT="" QUEUE="spot" VCPUS=2 MEMORY=4096 RUN_ID="" SYNC=120
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE_TAG="$2"; shift 2 ;;
    --experiment) EXPERIMENT="$2"; shift 2 ;;
    --queue) QUEUE="$2"; shift 2 ;;
    --vcpus) VCPUS="$2"; shift 2 ;;
    --memory) MEMORY="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --sync-interval) SYNC="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$IMAGE_TAG" ] || [ -z "$EXPERIMENT" ] || [ $# -eq 0 ]; then
  sed -n '2,16p' "$0"
  exit 2
fi
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

require_platform
JOBDEF="${PREFIX}-$(echo "$IMAGE_TAG" | tr -c 'A-Za-z0-9_\n-' '-')"
JOBNAME="$(echo "${EXPERIMENT}-${RUN_ID}" | tr -c 'A-Za-z0-9_\n-' '-' | cut -c1-120)"

# One job definition per image tag, registered once (vCPU/memory are set per job below,
# so revisions do not pile up).
if [ "$(aws batch describe-job-definitions --job-definition-name "$JOBDEF" --status ACTIVE --query 'length(jobDefinitions)' --output text)" = "0" ]; then
  echo "registering job definition $JOBDEF"
  DEF=$(python3 -I - "$ECR_REPO:$IMAGE_TAG" "$JOB_ROLE_ARN" "$LOG_GROUP" "$RESULTS_BUCKET" "$REGION" <<'PY'
import json, sys
image, role, log_group, bucket, region = sys.argv[1:6]
print(json.dumps({
    "image": image,
    "jobRoleArn": role,
    "resourceRequirements": [{"type": "VCPU", "value": "1"}, {"type": "MEMORY", "value": "1024"}],
    "environment": [{"name": "RESULTS_BUCKET", "value": bucket}],
    "logConfiguration": {"logDriver": "awslogs", "options": {"awslogs-group": log_group, "awslogs-region": region}},
}))
PY
)
  # Spot reclaimed the machine -> retry (up to 5x). A real failure of your program -> stop.
  aws batch register-job-definition --job-definition-name "$JOBDEF" --type container --platform-capabilities EC2 \
    --container-properties "$DEF" \
    --retry-strategy '{"attempts":5,"evaluateOnExit":[{"onStatusReason":"Host EC2*","action":"RETRY"},{"onReason":"*","action":"EXIT"}]}' \
    --query jobDefinitionArn --output text >/dev/null
fi

OVERRIDES=$(python3 -I - "$VCPUS" "$MEMORY" "$EXPERIMENT" "$RUN_ID" "$SYNC" "$@" <<'PY'
import json, sys
vcpus, memory, experiment, run_id, sync, *command = sys.argv[1:]
print(json.dumps({
    "command": command,
    "resourceRequirements": [{"type": "VCPU", "value": vcpus}, {"type": "MEMORY", "value": memory}],
    "environment": [
        {"name": "EXPERIMENT", "value": experiment},
        {"name": "RUN_ID", "value": run_id},
        {"name": "SYNC_INTERVAL", "value": sync},
    ],
}))
PY
)

JOB_ID=$(aws batch submit-job --job-name "$JOBNAME" --job-queue "${PREFIX}-${QUEUE}" --job-definition "$JOBDEF" \
  --container-overrides "$OVERRIDES" --query jobId --output text)

cat <<EOF
submitted: $JOB_ID   (queue ${PREFIX}-${QUEUE}, ${VCPUS} vCPU, ${MEMORY} MiB)
run:       $EXPERIMENT / $RUN_ID
results:   s3://$RESULTS_BUCKET/runs/$EXPERIMENT/$RUN_ID/
state:     aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].[status,statusReason]' --output text
logs:      aws logs tail $LOG_GROUP --follow --log-stream-name-prefix $JOBDEF
EOF
