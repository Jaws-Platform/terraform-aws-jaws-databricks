# The workspace stack, applied after the account stack. Its databricks provider
# points at the workspace the account stack created.
#
# Workspace-level provider: host = the account stack's workspace_url output.
# Authentication comes from the environment (DATABRICKS_CLIENT_ID,
# DATABRICKS_CLIENT_SECRET); the service principal is a workspace admin.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "workspace_config" {
  source = "../../"

  users_group_name = "analytics-workspace-users"
  metastore_id     = "11111111-2222-3333-4444-555555555555"

  fixed_tags = {
    Project     = "analytics"
    Environment = "dev"
    CostCenter  = "cc-0000"
    Workspace   = "analytics-dev"
    Owner       = "data-team"
    ManagedBy   = "terraform"
  }

  compute_policies = {
    analytics-jobs = {
      description = "Small autoscaling jobs compute"
      definition = jsonencode({
        autotermination_minutes = { type = "fixed", value = 30, hidden = true }
        node_type_id            = { type = "allowlist", values = ["m5.xlarge", "m5.2xlarge"] }
        num_workers             = { type = "range", maxValue = 4 }
      })
    }
  }

  # Only in the one governance workspace.
}

output "cluster_policy_ids" {
  value = module.workspace_config.cluster_policy_ids
}
