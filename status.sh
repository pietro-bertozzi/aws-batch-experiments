#!/usr/bin/env bash
# Shows what exists and what is active for the exp platform. Read-only.
# Usage: ./status.sh
set -uo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
P="$PREFIX"

hdr() { printf '\n== %s ==\n' "$1"; }

hdr "Active jobs (queue: status: count)"
queues=$(aws batch describe-job-queues --query "jobQueues[?starts_with(jobQueueName, '${P}-')].jobQueueName" --output text)
if [ -z "$queues" ]; then
  echo "(no exp queues: compute layer not deployed)"
else
  for q in $queues; do
    for s in SUBMITTED PENDING RUNNABLE STARTING RUNNING; do
      n=$(aws batch list-jobs --job-queue "$q" --job-status "$s" --query 'length(jobSummaryList)' --output text)
      [ "$n" != "0" ] && echo "$q: $s: $n"
    done
  done
  echo "(nothing listed above = no active jobs)"
fi

hdr "Batch compute environments (name, state, max vCPUs, current vCPUs)"
aws batch describe-compute-environments \
  --query "computeEnvironments[?starts_with(computeEnvironmentName, '${P}-')].[computeEnvironmentName,state,computeResources.maxvCpus,computeResources.desiredvCpus]" \
  --output text

hdr "Running EC2 instances tagged Project=${P} (these cost money)"
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=pending,running" "Name=tag:Project,Values=${P}" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,InstanceLifecycle,LaunchTime]' --output text
echo "(nothing listed above = no machines running)"

hdr "Job definitions still ACTIVE (old revisions pile up)"
aws batch describe-job-definitions --status ACTIVE \
  --query "jobDefinitions[?starts_with(jobDefinitionName, '${P}-')].[jobDefinitionName,revision]" --output text

hdr "S3 buckets"
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | sed 's/^/  /'

hdr "ECR repositories (images)"
for r in $(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text); do
  n=$(aws ecr list-images --repository-name "$r" --query 'length(imageIds)' --output text)
  echo "  $r: $n images"
done

hdr "IAM roles starting with ${P}-"
aws iam list-roles --query "Roles[?starts_with(RoleName, '${P}-')].RoleName" --output text | tr '\t' '\n' | sed 's/^/  /'

hdr "STRAYS: things in this region NOT named ${P}-* (not managed by this project)"
echo "Batch compute environments / queues:"
aws batch describe-compute-environments --query "computeEnvironments[?!starts_with(computeEnvironmentName, '${P}-')].computeEnvironmentName" --output text | tr '\t' '\n' | sed 's/^/  /'
aws batch describe-job-queues --query "jobQueues[?!starts_with(jobQueueName, '${P}-')].jobQueueName" --output text | tr '\t' '\n' | sed 's/^/  /'
echo "S3 buckets:"
aws s3api list-buckets --query "Buckets[?!starts_with(Name, '${P}-')].Name" --output text | tr '\t' '\n' | sed 's/^/  /'
echo "ECR repositories:"
aws ecr describe-repositories --query "repositories[?!starts_with(repositoryName, '${P}-')].repositoryName" --output text | tr '\t' '\n' | sed 's/^/  /'
echo "Unattached EBS volumes / Elastic IPs / NAT gateways (cost money if forgotten):"
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text | tr '\t' '\n' | sed 's/^/  volume /'
# shellcheck disable=SC2016  # backticks are JMESPath literals, not shell
aws ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].PublicIp' --output text | tr '\t' '\n' | sed 's/^/  eip /'
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId' --output text | tr '\t' '\n' | sed 's/^/  nat /'
echo
