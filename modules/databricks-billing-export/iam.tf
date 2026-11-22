# The credential's role, in the order Databricks documents (as in
# databricks-dataset): the credential names the role by a built ARN, and the
# role's trust comes from the credential's external ID. The role must be
# self-assuming, so its own policy allows assuming itself.

data "databricks_aws_unity_catalog_assume_role_policy" "this" {
  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = var.name
  external_id    = databricks_credential.this.aws_iam_role[0].external_id
}

resource "aws_iam_role" "this" {
  name               = var.name
  description        = "Databricks service credential ${var.name}: writes billing snapshots"
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.this.json

  tags = local.tags
}

# Put only, and only under the prefix: the job can add snapshots but never read,
# list, overwrite elsewhere or delete anything in the bucket.
resource "aws_iam_role_policy" "this" {
  name = "put-billing-snapshots"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PutSnapshots"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${local.bucket_arn}/${var.prefix}/*"
      },
      {
        Sid      = "SelfAssume"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.role_arn
      },
    ]
  })
}

resource "time_sleep" "role_propagation" {
  create_duration = "30s"

  depends_on = [aws_iam_role.this, aws_iam_role_policy.this]
}
