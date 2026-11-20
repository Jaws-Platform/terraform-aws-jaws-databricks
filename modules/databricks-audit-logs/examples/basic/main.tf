locals {
  # Modules take no tag map. Every resource inherits these through the
  # provider's default_tags, and each module adds `Component` (and `Name`).
  tags = {
    Organization = "acme"
    Project      = "analytics"
    Environment  = "prod"
    Repository   = "example/infra"
    ManagedBy    = "terraform"
    Owner        = "platform-team"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

# Account-level provider; authentication comes from the environment.
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "audit_logs" {
  source = "../../"

  bucket_name = "acme-databricks-audit-logs"
  role_name   = "acme-databricks-log-delivery"
  account_id  = "11111111-2222-3333-4444-555555555555"
}

output "bucket_arn" {
  value = module.audit_logs.bucket_arn
}
