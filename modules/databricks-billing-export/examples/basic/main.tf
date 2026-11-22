# The Databricks billing export, in the host workspace of an account, writing to
# the billing bucket acme-billing. The workspace provider authenticates as the
# identity the job will run as.

provider "aws" {
  region = "us-east-1"
}

provider "databricks" {
  host = "https://acme-shared.cloud.databricks.com"
}

module "billing_export" {
  source = "../.."

  name             = "acme-billing-export"
  bucket_name      = "acme-billing"
  owner_group_name = "acme-metastore-admins"
}

output "job_id" {
  value = module.billing_export.job_id
}
