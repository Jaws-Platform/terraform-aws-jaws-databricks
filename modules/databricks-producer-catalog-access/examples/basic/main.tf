# Applied through the shared-objects host: the workspace-level provider's
# host is databricks-host-workspace's workspace_url.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "chess_selfplay_access" {
  source = "../../"

  catalog_name     = "chess_selfplay"
  owner_group_name = "acme-metastore-admins"

  consumers = {
    analytics = { workspace_id = 2222222222222222, users_group_name = "analytics-workspace-users" }
  }
}

output "consumers" {
  value = module.chess_selfplay_access.consumers
}
