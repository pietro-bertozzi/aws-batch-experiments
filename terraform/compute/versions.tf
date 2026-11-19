# COMPUTE: the Batch machinery. Free when idle, safe to destroy and recreate
# at any time -- it never holds data. Needs ../foundation applied first.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  backend "s3" {
    key          = "exp/compute.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = { Project = var.name, Layer = "compute", ManagedBy = "terraform" }
  }
}
