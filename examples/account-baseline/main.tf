# Stack 1 of 4, applied once per Databricks account: the Unity Catalog
# metastore, audit log delivery and the shared-objects host workspace.

variable "databricks_account_id" {
  description = "Databricks account ID (a UUID), from the account console."
  type        = string
}

variable "service_principal_application_id" {
  description = "Application (client) ID of the account-admin service principal Terraform authenticates as."
  type        = string
}

provider "aws" {
  region = "us-east-1"

  # The modules take no tag map. Every AWS resource inherits these, and each
  # module adds `Component` and `Name`.
  default_tags {
    tags = {
      Project     = "data-platform"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

# The account-level API. Authentication comes from the environment:
# DATABRICKS_ACCOUNT_ID, and DATABRICKS_CLIENT_ID and DATABRICKS_CLIENT_SECRET
# of a service principal that is an account admin.
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "databricks" {
  source = "../../"

  account_id = var.databricks_account_id
  name_root  = "acme"

  # People who administer the metastore. They must already be account users.
  admin_user_names                 = ["owner@example.com"]
  service_principal_application_id = var.service_principal_application_id

  # Databricks puts these on the host workspace. `Workspace` defaults to its
  # name, `acme-shared`.
  tags = {
    Project     = "data-platform"
    Environment = "prod"
    CostCenter  = "platform"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}

output "metastore_id" {
  description = "For each project's workspace."
  value       = module.databricks.metastore_id
}

output "admin_group_name" {
  description = "The group that owns the metastore and every shared dataset."
  value       = module.databricks.admin_group_name
}

output "host_workspace_id" {
  description = "For the dataset-sharing stack."
  value       = module.databricks.host_workspace_id
}

output "host_workspace_url" {
  description = "The `host` of the dataset-sharing stack's databricks provider."
  value       = module.databricks.host_workspace_url
}
