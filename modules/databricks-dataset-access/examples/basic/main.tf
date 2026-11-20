# Applied through the shared-objects host, like databricks-dataset: the
# workspace-level provider's host is databricks-host-workspace's workspace_url.
# Authentication comes from the environment.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "positions_access" {
  source = "../../"

  external_location_name  = "acme-ds-chess-selfplay-positions"
  storage_credential_name = "acme-ds-chess-selfplay-positions"
  owner_group_name        = "acme-metastore-admins"
  schema_full_name        = "chess_selfplay.positions"
  volume_full_name        = "chess_selfplay.positions.files"

  consumers = {
    analytics = { workspace_id = 2222222222222222, users_group_name = "analytics-workspace-users" }
  }
}

output "consumers" {
  value = module.positions_access.consumers
}
