# ------------------------------------------------------------------------------
# CloudWatch Observability - IAM role for Container Insights
#
# The amazon-cloudwatch-observability addon uses Pod Identity to access
# CloudWatch and X-Ray. This creates the IAM role with least-privilege
# policies and associates it with the cloudwatch-agent service account.
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "cloudwatch_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch" {
  name               = "${var.project_name}-cloudwatch-observability"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_assume.json

  tags = {
    Purpose = "CloudWatch Container Insights for EKS Auto Mode"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "xray_write" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}
