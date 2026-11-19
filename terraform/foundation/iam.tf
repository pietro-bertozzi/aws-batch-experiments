data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Role for the EC2 machines Batch starts (lets them join ECS, pull from ECR, write logs).
resource "aws_iam_role" "instance" {
  name               = "${var.name}-batch-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_ecs" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-batch-instance"
  role = aws_iam_role.instance.name
}

# Role your Python code runs as inside the container: can read/write ONLY the results bucket.
resource "aws_iam_role" "job" {
  name               = "${var.name}-batch-job"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "job_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.results.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.results.arn}/*"]
  }
}

resource "aws_iam_role_policy" "job_s3" {
  name   = "results-bucket"
  role   = aws_iam_role.job.id
  policy = data.aws_iam_policy_document.job_s3.json
}
