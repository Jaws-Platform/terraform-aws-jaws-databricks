# The Databricks billing export: a daily serverless job in a workspace (the
# shared-objects host) that writes whole-billing-period snapshots of
# system.billing.usage and system.billing.list_prices (and optionally the
# workspace names) to the billing bucket, for billing-normalizer.
#
#   credential   a Unity Catalog SERVICE credential on an IAM role that may
#                only put objects under var.prefix
#   job          files/billing_export.py, run daily on serverless compute in
#                standard performance mode, as the identity applying this module
#   grants       that identity may use the system catalog, read system.billing
#                (and system.access) and use the credential; all additive

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# The identity this module is applied as: the job runs as it, and it is granted
# what the job reads. For a service principal, user_name is its application ID.
data "databricks_current_user" "me" {}

locals {
  # Built from the name, never from aws_iam_role.this: the role's trust needs
  # the credential's external ID, so the credential cannot depend on the role.
  role_arn   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}"
  bucket_arn = "arn:aws:s3:::${var.bucket_name}"
  run_as     = data.databricks_current_user.me.user_name

  tags = {
    Name      = var.name
    Component = var.component
  }
}

# Open rather than bound to one workspace: only principals granted ACCESS (the
# job's identity) and the owner group can use it, and it can only put objects
# under var.prefix. Validation is skipped because the role's trust can only be
# written once the credential's external ID exists.
resource "databricks_credential" "this" {
  name            = var.name
  purpose         = "SERVICE"
  comment         = "Writes Databricks billing snapshots to s3://${var.bucket_name}/${var.prefix}/; managed by Terraform"
  owner           = var.owner_group_name
  isolation_mode  = "ISOLATION_MODE_OPEN"
  skip_validation = true
  force_destroy   = true

  aws_iam_role {
    role_arn = local.role_arn
  }
}
