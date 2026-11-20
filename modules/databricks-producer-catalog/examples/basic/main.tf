# Applied through the shared-objects host: the workspace-level provider's
# host is databricks-host-workspace's workspace_url.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "chess_selfplay" {
  source = "../../"

  producer          = "chess-selfplay"
  storage_url       = "s3://acme-dataset-catalogs/managed"
  host_workspace_id = 1111111111111111
  owner_group_name  = "acme-metastore-admins"
}

output "catalog_name" {
  value = module.chess_selfplay.catalog_name
}
