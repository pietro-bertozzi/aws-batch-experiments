# Look up what we need from the foundation layer, by name (no cross-state coupling).
data "aws_iam_instance_profile" "instance" {
  name = "${var.name}-batch-instance"
}
