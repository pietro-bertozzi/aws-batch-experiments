# Design decisions

Short records of what was chosen, what was rejected, and why. Each entry stands alone.

## 1. AWS Batch on EC2 (not Fargate, SageMaker, or EKS)

**Need:** run many containerised jobs, some long, in parallel, cheaply, with nothing running
when idle.

**Chosen:** AWS Batch with EC2 compute environments. It provides a queue, retries, Spot and
scale-to-zero without us building them.

**Rejected:**
- Lambda: 15 minute limit.
- Plain EC2 plus a script: we would rebuild a worse Batch (queue, retries, shutdown).
- ECS/Fargate tasks directly: no queue. Batch on Fargate: roughly twice the cost per vCPU
  (from memory, unverified), a 16 vCPU cap, no GPU. Also explicitly not wanted.
- SageMaker jobs: good for ML, pricier, ML-shaped.
- EKS, Ray, Dask: far more to operate than the problem needs.

**Could add later:** a workflow engine (Nextflow, Snakemake, Metaflow) on top of Batch.

## 2. Spot by default, plus an on-demand queue

Spot is the cheap default; jobs must checkpoint (decision 4). The on-demand queue is the
fallback for jobs that cannot tolerate interruption or when Spot capacity is short. Both
environments scale to zero (`min_vcpus = 0`). `max_vcpus` equals the account's current
quota (32 Spot, 16 on-demand) and is the real spending brake.

Compute environments are a map in `terraform/compute/variables.tf`; adding another kind
(for example GPU) is a new entry. Deleting an entry removes it.

## 3. Two Terraform layers

`foundation/` holds long-lived things (results, images, IAM, logs, budget). `compute/`
holds the Batch machinery, which is free when idle and holds no data, so it can be destroyed
and recreated without risk. `compute/` finds foundation resources by name, not by reading
its state, so the layers stay independent. `bootstrap/` creates the state bucket and keeps
its own state locally (the usual chicken-and-egg).

## 4. Language-agnostic jobs via a file contract

Jobs see two plain folders (`$OUTPUT_DIR`, `$CHECKPOINT_DIR`); `platform/exp-wrapper.sh`
syncs them with S3 and forwards the shutdown signal to the program. The program needs no AWS
SDK and can be written in any language. Cost: every image needs the AWS CLI. Limit: Spot
gives about 2 minutes' warning, so programs must still checkpoint regularly; the wrapper
only uploads what is already on disk.

## 5. Job definitions are created by `run.sh`, not Terraform

Batch cannot override the image at submit time, so each image needs its own job definition.
Managing those in Terraform would make every new image a Terraform change. `run.sh`
registers one definition per image tag, once (vCPU and memory are set per job, so revisions
do not pile up). Trade-off: these definitions are outside Terraform state;
`teardown.sh` deregisters them and `status.sh` lists them.

## 6. Default VPC, public subnets, no NAT gateway

Machines get public IPs and a security group with no inbound rules. A NAT gateway would cost
about $32/month for no benefit here. Trade-off: machines are directly on the internet
(outbound only). If the threat model changes, move to private subnets with VPC endpoints.

## 7. Free plan: free-tier eligible instance types only

Found by testing: on the AWS free plan every launch of any other instance type is refused
(`The specified instance type is not eligible for Free Tier`), and Batch jobs sit in
`RUNNABLE` forever with no error on the job itself. The cause shows in the Auto Scaling
group's scaling activities. Hence `c7i-flex` and `m7i-flex`, which limits jobs to
2 vCPUs and 8 GB. Check with `aws ec2 describe-instance-types --filters
Name=free-tier-eligible,Values=true`.

## 8. Budget alerts only notify

One AWS Budget with eight alert levels (one budget with many alerts is free; separate
budgets beyond the first two are paid). Alerts arrive hours late and cannot stop spending.

## 9. Security choices that a reviewer may question

- **Job role** can only read/write the results bucket. **Instance role** uses the AWS
  managed ECS policy, which ECS requires and is broader than minimal.
- **ECR tags are mutable** so re-pushing a tag works; images are scanned on push. Pin by
  digest if you need exact reproducibility.
- **Results bucket** denies non-HTTPS access and blocks public access. It is not versioned.
- **Deploys use a full-access role.** There is no separate least-privilege deploy role.

## 10. Scripts share one naming module

`lib.sh` is the only place the scripts define resource names; Terraform defines the same
names. They are kept in sync by convention, and `require_platform` fails with a clear
message if they drift.
