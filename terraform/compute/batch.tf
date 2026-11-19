# Network: use the account's default VPC (public subnets, no NAT gateway = no NAT cost).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Outbound-only: containers can reach S3/ECR/internet, nothing can connect in.
resource "aws_security_group" "batch" {
  name        = "${var.name}-batch"
  description = "Batch instances: egress only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- One compute environment + one queue per entry in var.compute_environments ---
resource "aws_batch_compute_environment" "this" {
  for_each = var.compute_environments

  name_prefix = "${var.name}-${each.key}-"
  type        = "MANAGED"

  compute_resources {
    type                = each.value.spot ? "SPOT" : "EC2"
    allocation_strategy = each.value.spot ? "SPOT_PRICE_CAPACITY_OPTIMIZED" : "BEST_FIT_PROGRESSIVE"

    min_vcpus     = 0 # scale to zero when idle = no cost
    desired_vcpus = 0
    max_vcpus     = each.value.max_vcpus

    instance_type      = each.value.instance_types
    instance_role      = data.aws_iam_instance_profile.instance.arn
    subnets            = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.batch.id]
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [compute_resources[0].desired_vcpus]
  }

  # Batch's service-linked role is created automatically by AWS on first use.
}

resource "aws_batch_job_queue" "this" {
  for_each = var.compute_environments

  name     = "${var.name}-${each.key}"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.this[each.key].arn
  }
}

