# Account-level provider; authentication comes from the environment
# (DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET, DATABRICKS_ACCOUNT_ID).
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "host" {
  source = "../../"

  workspace_name   = "acme-shared"
  account_id       = "11111111-2222-3333-4444-555555555555"
  metastore_id     = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  admin_group_name = "acme-metastore-admins"

  tags = {
    Project     = "shared"
    Environment = "prod"
    CostCenter  = "platform"
    Workspace   = "acme-shared"
    Owner       = "owner"
    ManagedBy   = "terraform"
  }
}

output "workspace_url" {
  value = module.host.workspace_url
}
